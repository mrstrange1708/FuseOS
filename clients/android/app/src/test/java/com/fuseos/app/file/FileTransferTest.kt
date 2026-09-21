package com.fuseos.app.file

import com.fuseos.proto.Envelope
import com.google.protobuf.ByteString
import java.io.ByteArrayInputStream
import java.io.File
import java.security.MessageDigest
import kotlin.random.Random
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Drives a sender straight into a receiver, which is the pair that has to agree — the
 * macOS `FileTransferTests` runs the same shapes against the same wire format, so the two
 * clients are tested against one contract rather than against each other's assumptions.
 */
class FileTransferTest {

    private val root = File(System.getProperty("java.io.tmpdir"), "fuse-file-${Random.nextLong()}")
    private val sent = mutableListOf<Envelope>()
    private var received = mutableListOf<ReceivedFile>()
    private var seq = 0L

    private val sender = FileTransfer(File(root, "out"), ::envelope) { sent += it }
    private val receiver = FileTransfer(File(root, "in"), ::envelope) { sent += it }

    private val senderProgress = mutableListOf<TransferProgress>()
    private val receiverProgress = mutableListOf<TransferProgress>()

    init {
        receiver.onFileReceived = { received += it }
        sender.onProgress = { senderProgress += it }
        receiver.onProgress = { receiverProgress += it }
    }

    /** Feeds whatever the receiver emitted (ack, cancel) back to the sender. */
    private fun replyAll() {
        val envelopes = sent.toList()
        sent.clear()
        envelopes.forEach { sender.receive(it) }
    }

    private fun inbox() = File(root, "in").listFiles().orEmpty().toList()

    @After
    fun tearDown() {
        sender.stop()
        receiver.stop()
        root.deleteRecursively()
    }

    private fun envelope(): Envelope.Builder =
        Envelope.newBuilder().setSourceDeviceId("device-a").setSeq(++seq).setSessionId("session")

    /** Everything the sender emitted, replayed into the receiver in wire order. */
    private fun deliverAll() {
        val envelopes = sent.toList()
        sent.clear()
        envelopes.forEach { receiver.receive(it) }
    }

    private fun sendBytes(bytes: ByteArray, name: String = "notes.txt"): String? =
        sender.send(name, "text/plain", bytes.size.toLong()) { ByteArrayInputStream(bytes) }

    @Test
    fun `a file arrives byte-identical and is acknowledged`() {
        // Deliberately several chunks plus a partial one — off-by-one on the last chunk is
        // the failure this catches.
        val bytes = Random(7).nextBytes(FileTransfer.CHUNK_BYTES * 2 + 123)
        assertNotNull(sendBytes(bytes))
        deliverAll()

        assertEquals(1, received.size)
        assertArrayEquals(bytes, received.single().file.readBytes())
        assertEquals("notes.txt", received.single().name)
        assertEquals(1, sent.count { it.bodyCase == Envelope.BodyCase.ACK })
    }

    @Test
    fun `a file that is exactly one chunk still terminates`() {
        val bytes = Random(1).nextBytes(FileTransfer.CHUNK_BYTES)
        assertNotNull(sendBytes(bytes))
        deliverAll()
        assertArrayEquals(bytes, received.single().file.readBytes())
    }

    @Test
    fun `a corrupted chunk is discarded rather than written out`() {
        val bytes = Random(3).nextBytes(FileTransfer.CHUNK_BYTES + 10)
        sendBytes(bytes)
        val envelopes = sent.toList().map { envelope ->
            if (envelope.bodyCase != Envelope.BodyCase.FILE_CHUNK || envelope.fileChunk.index != 0L) {
                envelope
            } else {
                envelope.toBuilder().setFileChunk(
                    envelope.fileChunk.toBuilder().setData(
                        ByteString.copyFrom(ByteArray(FileTransfer.CHUNK_BYTES)),
                    ),
                ).build()
            }
        }
        sent.clear()
        envelopes.forEach { receiver.receive(it) }

        assertTrue(received.isEmpty())
        assertTrue(sent.none { it.bodyCase == Envelope.BodyCase.ACK })
        // And nothing is left behind on disk — not the partial, not a half file.
        assertTrue(File(root, "in").listFiles().orEmpty().isEmpty())
    }

    @Test
    fun `a chunk out of order abandons the transfer`() {
        val bytes = Random(5).nextBytes(FileTransfer.CHUNK_BYTES * 2)
        sendBytes(bytes)
        val envelopes = sent.toList()
        sent.clear()
        // Drop chunk 0: chunk 1 then arrives where 0 was expected.
        envelopes.filterNot {
            it.bodyCase == Envelope.BodyCase.FILE_CHUNK && it.fileChunk.index == 0L
        }.forEach { receiver.receive(it) }

        assertTrue(received.isEmpty())
        assertTrue(File(root, "in").listFiles().orEmpty().isEmpty())
    }

    @Test
    fun `two files of the same name both survive`() {
        val first = Random(11).nextBytes(64)
        val second = Random(12).nextBytes(64)
        sendBytes(first)
        deliverAll()
        sendBytes(second)
        deliverAll()

        assertEquals(2, received.size)
        assertArrayEquals(first, received[0].file.readBytes())
        assertArrayEquals(second, received[1].file.readBytes())
        assertFalse(received[0].file.name == received[1].file.name)
    }

    @Test
    fun `an empty file is refused rather than sent`() {
        assertNull(sendBytes(ByteArray(0)))
        assertTrue(sent.isEmpty())
    }

    @Test
    fun `the checksum on the wire is the sha-256 of the content`() {
        val bytes = Random(13).nextBytes(1000)
        sendBytes(bytes)
        val meta = sent.first { it.bodyCase == Envelope.BodyCase.FILE_META }.fileMeta
        val expected = MessageDigest.getInstance("SHA-256").digest(bytes)
            .joinToString("") { "%02x".format(it) }
        assertEquals(expected, meta.checksum)
        assertEquals(bytes.size.toLong(), meta.size)
    }

    @Test
    fun `a peer cannot write outside the download directory`() {
        assertEquals("passwd", FileTransfer.safeName("../../../etc/passwd"))
        assertEquals("file", FileTransfer.safeName(".."))
        assertEquals("file", FileTransfer.safeName(""))
        assertEquals("notes.txt", FileTransfer.safeName("notes.txt"))
    }

    @Test
    fun `a name a peer chose is confined to the directory on a real transfer`() {
        val bytes = Random(17).nextBytes(32)
        sender.send("../../escape.txt", "text/plain", bytes.size.toLong()) {
            ByteArrayInputStream(bytes)
        }
        deliverAll()
        assertEquals(File(root, "in"), received.single().file.parentFile)
        assertEquals("escape.txt", received.single().name)
    }

    @Test
    fun `a send is done only once the receiver acknowledges it`() {
        val bytes = Random(19).nextBytes(FileTransfer.CHUNK_BYTES * 3)
        val id = sendBytes(bytes)!!
        assertEquals(TransferProgress.State.Sent, senderProgress.last().state)
        deliverAll()
        assertEquals(TransferProgress.State.Done, receiverProgress.last().state)
        replyAll()
        assertEquals(TransferProgress.State.Done, senderProgress.last().state)
        assertEquals(id, senderProgress.last().transferId)
        assertEquals(bytes.size.toLong(), senderProgress.last().bytes)
    }

    @Test
    fun `cancelling a send stops the stream and the receiver discards its partial`() {
        val bytes = Random(23).nextBytes(FileTransfer.CHUNK_BYTES * 10)
        // Cancel from inside the stream, the way the UI's button lands mid-transfer.
        val cancelling = FileTransfer(File(root, "out2"), ::envelope) { envelope ->
            sent += envelope
            if (envelope.bodyCase == Envelope.BodyCase.FILE_CHUNK && envelope.fileChunk.index == 2L) {
                sentCancel?.invoke()
            }
        }
        cancelling.onProgress = { senderProgress += it }
        sentCancel = { cancelling.cancel(senderProgress.first().transferId) }

        assertNull(cancelling.send("big.bin", "application/octet-stream", bytes.size.toLong()) {
            ByteArrayInputStream(bytes)
        })
        assertEquals(3, sent.count { it.bodyCase == Envelope.BodyCase.FILE_CHUNK })
        assertEquals(TransferProgress.State.Cancelled, senderProgress.last().state)

        deliverAll()
        assertTrue(received.isEmpty())
        assertTrue(inbox().isEmpty())
        assertEquals(TransferProgress.State.Failed, receiverProgress.last().state)
    }

    private var sentCancel: (() -> Unit)? = null

    @Test
    fun `cancelling a receive tells the sender`() {
        val bytes = Random(29).nextBytes(FileTransfer.CHUNK_BYTES * 2)
        sendBytes(bytes)
        val envelopes = sent.toList()
        sent.clear()
        receiver.receive(envelopes.first()) // meta only
        val id = receiverProgress.single().transferId
        receiver.cancel(id)

        assertTrue(inbox().isEmpty())
        assertEquals(TransferProgress.State.Cancelled, receiverProgress.last().state)
        assertEquals(Envelope.BodyCase.FILE_CANCEL, sent.single().bodyCase)
        replyAll()
        assertEquals(TransferProgress.State.Failed, senderProgress.last().state)
    }

    @Test
    fun `a file that fails verification fails the send too, rather than waiting forever`() {
        val bytes = Random(31).nextBytes(100)
        sendBytes(bytes)
        val envelopes = sent.toList().map { envelope ->
            if (envelope.bodyCase != Envelope.BodyCase.FILE_CHUNK) {
                envelope
            } else {
                envelope.toBuilder().setFileChunk(
                    envelope.fileChunk.toBuilder().setData(ByteString.copyFrom(ByteArray(100))),
                ).build()
            }
        }
        sent.clear()
        envelopes.forEach { receiver.receive(it) }
        replyAll()
        assertEquals(TransferProgress.State.Failed, senderProgress.last().state)
    }

    @Test
    fun `a peer dropping mid-transfer discards its partial file`() {
        val bytes = Random(37).nextBytes(FileTransfer.CHUNK_BYTES * 3)
        sendBytes(bytes)
        sent.take(2).forEach { receiver.receive(it) } // meta + first chunk
        assertEquals(1, inbox().size) // the partial

        receiver.onPeersChanged(setOf("some-other-device"))
        assertTrue(inbox().isEmpty())
        assertEquals(TransferProgress.State.Failed, receiverProgress.last().state)
    }

    @Test
    fun `a partial left by a killed process is swept on the next start`() {
        val inbox = File(root, "in").apply { mkdirs() }
        File(inbox, ".partial-stale").writeText("half a file")
        File(inbox, "kept.txt").writeText("a real file")
        FileTransfer(inbox, ::envelope) {}
        assertEquals(listOf("kept.txt"), inbox.list()!!.toList())
    }

    @Test
    fun `progress is throttled rather than reported per chunk`() {
        val bytes = Random(41).nextBytes(FileTransfer.CHUNK_BYTES * 400)
        sendBytes(bytes)
        // 400 chunks, ~1% steps: about 100 reports, never one per chunk.
        assertTrue(senderProgress.size in 50..120)
    }
}
