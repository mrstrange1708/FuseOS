package com.fuseos.app.file

import com.fuseos.proto.Ack
import com.fuseos.proto.Envelope
import com.fuseos.proto.FileCancel
import com.fuseos.proto.FileChunk
import com.fuseos.proto.FileMeta
import com.google.protobuf.ByteString
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/** A file that arrived from a peer, verified and already on disk. */
data class ReceivedFile(
    val transferId: String,
    val file: File,
    val name: String,
    val mime: String,
    val size: Long,
)

/**
 * Where one transfer is, for the progress UI. [bytes] of [total] moves as chunks go out or
 * come in; [state] is what the row says.
 */
data class TransferProgress(
    val transferId: String,
    val name: String,
    val outgoing: Boolean,
    val bytes: Long,
    val total: Long,
    val state: State,
) {
    enum class State {
        /** Chunks are moving. */
        Active,

        /** Every chunk is out; waiting for the receiver's verified [Ack]. Outgoing only. */
        Sent,

        /** Acknowledged (outgoing) or verified and on disk (incoming). */
        Done,

        /** This device cancelled it. */
        Cancelled,

        /** The other end gave up, the link dropped, or the file failed verification. */
        Failed,
    }

    val finished get() = state == State.Done || state == State.Cancelled || state == State.Failed
}

/**
 * File transfer over the LAN data plane. The macOS `FileTransfer` is the mirror of this
 * file; the two must stay in step, because the only thing between them is `proto/`.
 *
 * The flow is `docs/protocol.md` §6: one [FileMeta] (name, size, mime, sha-256), then
 * ordered [FileChunk]s, then an [Ack] from the receiver once the checksum matches.
 *
 * Deliberately not resumable. A dropped connection abandons the partial file and the user
 * re-sends — which on a LAN costs seconds, and costs far less code than a resume protocol
 * that would have to survive both ends restarting.
 *
 * Nothing here touches an Android API: a transfer is "mint an envelope, emit it, write to
 * a directory", which is also what makes it testable on the JVM without a device.
 */
class FileTransfer(
    private val directory: File,
    private val newEnvelope: () -> Envelope.Builder,
    private val emit: (Envelope) -> Unit,
) {
    /**
     * Fires once per file, after the checksum has been verified. Nothing is published for
     * a transfer that fails — a corrupt file is not an event worth showing anyone.
     */
    var onFileReceived: ((ReceivedFile) -> Unit)? = null

    /**
     * Every state change and roughly every 1% of bytes, from whichever thread did the work.
     * Throttled because a 1 GiB file is 16k chunks, and a UI does not need 16k redraws.
     */
    var onProgress: ((TransferProgress) -> Unit)? = null

    private val receiving = mutableMapOf<String, Reception>()
    private val sending = ConcurrentHashMap<String, Outgoing>()

    init {
        // A partial is only ever alive inside one process: one left on disk is from a run
        // that was killed mid-transfer, and nothing will ever finish it.
        directory.listFiles { file -> file.name.startsWith(PARTIAL_PREFIX) }?.forEach { it.delete() }
    }

    /** Abandons every partial transfer. Called on teardown; the temp files go with it. */
    fun stop() {
        synchronized(receiving) {
            receiving.values.forEach { it.discard() }
            receiving.clear()
        }
        sending.values.forEach { it.cancelled = true }
        sending.clear()
    }

    /**
     * Stops a transfer in either direction and tells the other end, which discards its
     * side. A no-op for an id that already finished.
     */
    fun cancel(transferId: String) {
        sending.remove(transferId)?.let { outgoing ->
            // The send loop sees the flag at its next chunk and stops without another word;
            // the cancel below is what the receiver acts on.
            outgoing.cancelled = true
            emitCancel(transferId)
            report(outgoing.progress(TransferProgress.State.Cancelled))
            return
        }
        val reception = synchronized(receiving) { receiving.remove(transferId) } ?: return
        reception.discard()
        emitCancel(transferId)
        report(reception.progress(TransferProgress.State.Cancelled))
    }

    /**
     * Fails whatever cannot finish now that only [connected] peers are reachable: an
     * incoming file from a peer that dropped will never get its last chunk, and with nobody
     * connected an outgoing one will never be acknowledged.
     */
    fun onPeersChanged(connected: Set<String>) {
        val orphaned = synchronized(receiving) {
            receiving.values.filter { it.sourceDeviceId !in connected }
                .onEach { receiving.remove(it.transferId) }
        }
        orphaned.forEach {
            it.discard()
            report(it.progress(TransferProgress.State.Failed))
        }
        if (connected.isEmpty()) {
            sending.keys.toList().forEach { id ->
                sending.remove(id)?.let {
                    it.cancelled = true
                    report(it.progress(TransferProgress.State.Failed))
                }
            }
        }
    }

    // ---- sending ----

    /**
     * Streams a file to every connected peer, returning its transfer id.
     *
     * Two passes over the content — [open] is called twice. [FileMeta] has to carry the
     * checksum and the receiver has to verify before it commits the file anywhere, so the
     * hash cannot be computed as we go.
     *
     * Blocking: call it on [kotlinx.coroutines.Dispatchers.IO]. Returns null when the
     * content is unusable, so the caller can say so rather than silently dropping it.
     */
    fun send(name: String, mime: String, size: Long, open: () -> InputStream): String? {
        if (size <= 0 || size > MAX_FILE_BYTES) return null

        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(CHUNK_BYTES)
        try {
            open().use { stream ->
                while (true) {
                    val read = stream.read(buffer)
                    if (read <= 0) break
                    digest.update(buffer, 0, read)
                }
            }
        } catch (e: Exception) {
            return null
        }

        val transferId = UUID.randomUUID().toString()
        val outgoing = Outgoing(transferId, safeName(name), size)
        sending[transferId] = outgoing
        report(outgoing.progress(TransferProgress.State.Active))
        emit(
            newEnvelope().setFileMeta(
                FileMeta.newBuilder()
                    .setTransferId(transferId)
                    .setName(safeName(name))
                    .setSize(size)
                    .setMime(mime)
                    .setChecksum(digest.digest().toHex()),
            ).build(),
        )

        try {
            open().use { stream ->
                var index = 0L
                var sent = 0L
                while (true) {
                    // Cancelled from the UI, or failed by a dropped peer: whoever set the
                    // flag has already reported it and told the receiver.
                    if (outgoing.cancelled) return null
                    val read = stream.read(buffer)
                    val length = if (read > 0) read else 0
                    sent += length
                    // The content shrinking mid-send ends the stream here; the receiver's
                    // checksum catches it, the same check that catches a corrupt chunk.
                    val last = length == 0 || sent >= size
                    emit(
                        newEnvelope().setFileChunk(
                            FileChunk.newBuilder()
                                .setTransferId(transferId)
                                .setIndex(index)
                                .setData(ByteString.copyFrom(buffer, 0, length))
                                .setLast(last),
                        ).build(),
                    )
                    // Checked after the write as well: a cancel that lands while a chunk
                    // is on its way must not be followed by an "Active" report.
                    if (outgoing.cancelled) return null
                    outgoing.bytes = sent
                    if (last) break
                    index++
                    if (outgoing.shouldReport()) report(outgoing.progress(TransferProgress.State.Active))
                }
            }
        } catch (e: Exception) {
            // Unreadable halfway: the receiver is holding a partial that will never
            // finish, so it has to be told rather than left to wait.
            if (sending.remove(transferId) != null) {
                emitCancel(transferId)
                report(outgoing.progress(TransferProgress.State.Failed))
            }
            return null
        }
        // Still ours unless an ack or a cancel raced the last chunk.
        if (sending.containsKey(transferId)) report(outgoing.progress(TransferProgress.State.Sent))
        return transferId
    }

    // ---- receiving ----

    /** Feed every [FileMeta] / [FileChunk] / [Ack] envelope here. Blocking (disk writes). */
    fun receive(envelope: Envelope) {
        when (envelope.bodyCase) {
            Envelope.BodyCase.FILE_META -> begin(envelope.fileMeta, envelope.sourceDeviceId)
            Envelope.BodyCase.FILE_CHUNK -> append(envelope.fileChunk)
            Envelope.BodyCase.ACK -> acknowledged(envelope.ack.refTransferId)
            Envelope.BodyCase.FILE_CANCEL -> cancelledRemotely(envelope.fileCancel.transferId)
            else -> Unit
        }
    }

    /** The receiver has the file and it verified: the only point a send is really done. */
    private fun acknowledged(transferId: String) {
        val outgoing = sending.remove(transferId) ?: return
        report(outgoing.progress(TransferProgress.State.Done, bytes = outgoing.size))
    }

    /** The other end gave up. Same handling whichever end of the transfer we are. */
    private fun cancelledRemotely(transferId: String) {
        sending.remove(transferId)?.let {
            it.cancelled = true
            report(it.progress(TransferProgress.State.Failed))
            return
        }
        val reception = synchronized(receiving) { receiving.remove(transferId) } ?: return
        reception.discard()
        report(reception.progress(TransferProgress.State.Failed))
    }

    private fun begin(meta: FileMeta, sourceDeviceId: String) {
        // Peer-supplied and therefore untrusted: a name is a *file* name, never a path, or
        // "../../databases/session" would be a valid transfer.
        val name = safeName(meta.name)
        if (meta.size <= 0 || meta.size > MAX_FILE_BYTES || meta.checksum.isEmpty()) return
        directory.mkdirs()
        val partial = File(directory, "$PARTIAL_PREFIX${safeName(meta.transferId)}")
        val reception = try {
            Reception(
                transferId = meta.transferId,
                sourceDeviceId = sourceDeviceId,
                name = name,
                mime = meta.mime,
                size = meta.size,
                checksum = meta.checksum.lowercase(),
                partial = partial,
                out = FileOutputStream(partial),
            )
        } catch (e: Exception) {
            return
        }
        synchronized(receiving) {
            // A repeated meta for a live transfer restarts it rather than corrupting it.
            receiving.put(meta.transferId, reception)?.discard()
        }
        report(reception.progress(TransferProgress.State.Active))
    }

    private fun append(chunk: FileChunk) {
        val reception = synchronized(receiving) { receiving[chunk.transferId] } ?: return
        // Ordering is the transport's job (TCP, one channel), so an out-of-order index
        // means something is wrong enough that the file cannot be trusted.
        if (chunk.index != reception.nextIndex) return abandon(reception)
        val bytes = chunk.data.toByteArray()
        reception.written += bytes.size
        if (reception.written > reception.size) return abandon(reception)
        try {
            reception.out.write(bytes)
        } catch (e: Exception) {
            return abandon(reception)
        }
        reception.digest.update(bytes)
        reception.nextIndex++
        if (chunk.last) return finish(reception)
        if (reception.shouldReport()) report(reception.progress(TransferProgress.State.Active))
    }

    private fun finish(reception: Reception) {
        synchronized(receiving) { receiving.remove(reception.transferId) }
        runCatching { reception.out.close() }

        if (reception.written != reception.size ||
            reception.digest.digest().toHex() != reception.checksum
        ) {
            return fail(reception)
        }

        val destination = uniqueFile(directory, reception.name)
        if (!reception.partial.renameTo(destination)) return fail(reception)
        report(reception.progress(TransferProgress.State.Done))
        onFileReceived?.invoke(
            ReceivedFile(
                transferId = reception.transferId,
                file = destination,
                name = destination.name,
                mime = reception.mime,
                size = reception.size,
            ),
        )
        emit(
            newEnvelope().setAck(Ack.newBuilder().setRefTransferId(reception.transferId)).build(),
        )
    }

    /** Drops a reception that went wrong, and tells the sender so it stops waiting. */
    private fun abandon(reception: Reception) {
        synchronized(receiving) { receiving.remove(reception.transferId) }
        fail(reception)
    }

    private fun fail(reception: Reception) {
        reception.discard()
        emitCancel(reception.transferId)
        report(reception.progress(TransferProgress.State.Failed))
    }

    private fun emitCancel(transferId: String) {
        emit(newEnvelope().setFileCancel(FileCancel.newBuilder().setTransferId(transferId)).build())
    }

    private fun report(progress: TransferProgress) {
        onProgress?.invoke(progress)
    }

    /** What both directions share: a byte count to report, throttled to about 1%. */
    private abstract class Tracked(val transferId: String, val name: String, val size: Long) {
        abstract val outgoing: Boolean
        abstract val bytesDone: Long
        private var reportedAt = 0L

        fun shouldReport(): Boolean {
            if (bytesDone - reportedAt < size / 100) return false
            reportedAt = bytesDone
            return true
        }

        fun progress(state: TransferProgress.State, bytes: Long = bytesDone) =
            TransferProgress(transferId, name, outgoing, bytes, size, state)
    }

    private class Outgoing(transferId: String, name: String, size: Long) : Tracked(transferId, name, size) {
        override val outgoing = true
        override val bytesDone get() = bytes

        @Volatile var bytes = 0L

        @Volatile var cancelled = false
    }

    private class Reception(
        transferId: String,
        val sourceDeviceId: String,
        name: String,
        val mime: String,
        size: Long,
        val checksum: String,
        val partial: File,
        val out: FileOutputStream,
    ) : Tracked(transferId, name, size) {
        override val outgoing = false
        override val bytesDone get() = written
        val digest: MessageDigest = MessageDigest.getInstance("SHA-256")
        var nextIndex = 0L
        var written = 0L

        fun discard() {
            runCatching { out.close() }
            partial.delete()
        }
    }

    companion object {
        /**
         * Small enough that a chunk is nowhere near [com.fuseos.app.net.LanChannel]'s 4 MB
         * frame cap even after protobuf framing and the GCM tag, large enough that a
         * 100 MB file is ~1600 frames rather than 100k.
         */
        const val CHUNK_BYTES = 64 * 1024

        /** Bounds what one peer can make this device write to disk in a single transfer. */
        const val MAX_FILE_BYTES = 1L shl 30 // 1 GiB

        private const val PARTIAL_PREFIX = ".partial-"

        /**
         * Reduces anything a peer sends to a plain file name. Internal so the traversal
         * cases are tested rather than assumed.
         */
        fun safeName(raw: String): String {
            val name = raw.substringAfterLast('/').substringAfterLast('\\').replace("\u0000", "")
            if (name.isEmpty() || name == "." || name == "..") return "file"
            return name.take(255)
        }

        /** Never overwrites: a second `report.pdf` becomes `report-1.pdf`. */
        fun uniqueFile(directory: File, name: String): File {
            val candidate = File(directory, name)
            if (!candidate.exists()) return candidate
            val base = name.substringBeforeLast('.', name)
            val extension = name.substringAfterLast('.', "")
            for (suffix in 1..999) {
                val numbered = if (extension.isEmpty()) "$base-$suffix" else "$base-$suffix.$extension"
                val file = File(directory, numbered)
                if (!file.exists()) return file
            }
            return File(directory, "$base-${UUID.randomUUID()}")
        }

        private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }
    }
}
