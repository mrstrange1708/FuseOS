package com.fuseos.app.file

import com.fuseos.proto.Ack
import com.fuseos.proto.Envelope
import com.fuseos.proto.FileChunk
import com.fuseos.proto.FileMeta
import com.google.protobuf.ByteString
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.security.MessageDigest
import java.util.UUID

/** A file that arrived from a peer, verified and already on disk. */
data class ReceivedFile(
    val transferId: String,
    val file: File,
    val name: String,
    val mime: String,
    val size: Long,
)

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

    private val receiving = mutableMapOf<String, Reception>()

    /** Abandons every partial transfer. Called on teardown; the temp files go with it. */
    fun stop() {
        synchronized(receiving) {
            receiving.values.forEach { it.discard() }
            receiving.clear()
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
                    if (last) break
                    index++
                }
            }
        } catch (e: Exception) {
            return null
        }
        return transferId
    }

    // ---- receiving ----

    /** Feed every [FileMeta] / [FileChunk] / [Ack] envelope here. Blocking (disk writes). */
    fun receive(envelope: Envelope) {
        when (envelope.bodyCase) {
            Envelope.BodyCase.FILE_META -> begin(envelope.fileMeta)
            Envelope.BodyCase.FILE_CHUNK -> append(envelope.fileChunk)
            // The sender has nothing left to do on an ack in v1 — no retry queue, no
            // resume. It stays on the wire because the receiver's "I have it, verified" is
            // what a progress UI will read, and adding it later would be a protocol change.
            else -> Unit
        }
    }

    private fun begin(meta: FileMeta) {
        // Peer-supplied and therefore untrusted: a name is a *file* name, never a path, or
        // "../../databases/session" would be a valid transfer.
        val name = safeName(meta.name)
        if (meta.size <= 0 || meta.size > MAX_FILE_BYTES || meta.checksum.isEmpty()) return
        directory.mkdirs()
        val partial = File(directory, ".partial-${safeName(meta.transferId)}")
        val reception = try {
            Reception(
                transferId = meta.transferId,
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
    }

    private fun append(chunk: FileChunk) {
        val reception = synchronized(receiving) { receiving[chunk.transferId] } ?: return
        // Ordering is the transport's job (TCP, one channel), so an out-of-order index
        // means something is wrong enough that the file cannot be trusted.
        if (chunk.index != reception.nextIndex) return abandon(chunk.transferId)
        val bytes = chunk.data.toByteArray()
        reception.written += bytes.size
        if (reception.written > reception.size) return abandon(chunk.transferId)
        try {
            reception.out.write(bytes)
        } catch (e: Exception) {
            return abandon(chunk.transferId)
        }
        reception.digest.update(bytes)
        reception.nextIndex++
        if (chunk.last) finish(reception)
    }

    private fun finish(reception: Reception) {
        synchronized(receiving) { receiving.remove(reception.transferId) }
        runCatching { reception.out.close() }

        if (reception.written != reception.size ||
            reception.digest.digest().toHex() != reception.checksum
        ) {
            reception.partial.delete()
            return
        }

        val destination = uniqueFile(directory, reception.name)
        if (!reception.partial.renameTo(destination)) {
            reception.partial.delete()
            return
        }
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

    private fun abandon(transferId: String) {
        synchronized(receiving) { receiving.remove(transferId) }?.discard()
    }

    private class Reception(
        val transferId: String,
        val name: String,
        val mime: String,
        val size: Long,
        val checksum: String,
        val partial: File,
        val out: FileOutputStream,
    ) {
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
