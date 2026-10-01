package com.fuseos.app.net

import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.Socket
import java.net.SocketTimeoutException
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

/**
 * What a [LanChannel] runs over: the bytes of the handshake and the sealed frames. A LAN
 * socket, or the relay through `/signal` — the channel, its keys and its checks are the same
 * either way, so the relay is exactly as private as the LAN (docs/protocol.md §18).
 */
interface Wire {
    val input: InputStream
    val output: OutputStream
    val viaRelay: Boolean

    /** A read with nothing to read for this long throws; 0 waits for ever. */
    fun setReadTimeout(ms: Int)
    fun close()
}

class SocketWire(private val socket: Socket) : Wire {
    init {
        runCatching { socket.tcpNoDelay = true } // latency is the product; never coalesce a frame
    }

    override val input: InputStream = socket.getInputStream()
    override val output: OutputStream = socket.getOutputStream()
    override val viaRelay = false
    override fun setReadTimeout(ms: Int) { runCatching { socket.soTimeout = ms } }
    override fun close() { runCatching { socket.close() } }
}

/**
 * One relayed channel to [peerId]. Writes collect until a flush, then leave as relay messages of
 * at most [CHUNK] bytes — one per sealed frame, in practice; reads take the pieces [deliver]
 * hands over, in order.
 */
class RelayWire(
    val peerId: String,
    val stream: String,
    private val send: (data: ByteArray?, close: Boolean) -> Boolean,
) : Wire {
    private val pieces = LinkedBlockingQueue<ByteArray>()
    @Volatile private var timeoutMs = 0
    @Volatile private var closed = false
    override val viaRelay = true

    fun deliver(bytes: ByteArray) {
        if (!closed) pieces.put(bytes)
    }

    /** The peer closed the stream: reads end. */
    fun end() {
        closed = true
        pieces.put(EOF)
    }

    override fun setReadTimeout(ms: Int) { timeoutMs = ms }

    override fun close() {
        if (closed) return
        send(null, true)
        end()
    }

    override val input: InputStream = object : InputStream() {
        private var current: ByteArray? = null
        private var at = 0

        override fun read(): Int {
            val one = ByteArray(1)
            return if (read(one, 0, 1) == -1) -1 else one[0].toInt() and 0xFF
        }

        override fun read(b: ByteArray, off: Int, len: Int): Int {
            if (len == 0) return 0
            var piece = current
            if (piece == null || at >= piece.size) {
                piece = if (timeoutMs > 0) {
                    pieces.poll(timeoutMs.toLong(), TimeUnit.MILLISECONDS) ?: throw SocketTimeoutException("relay read timed out")
                } else {
                    pieces.take()
                }
                if (piece === EOF) {
                    pieces.put(EOF) // every later read ends too
                    return -1
                }
                current = piece
                at = 0
            }
            val n = minOf(len, piece.size - at)
            System.arraycopy(piece, at, b, off, n)
            at += n
            return n
        }
    }

    override val output: OutputStream = object : OutputStream() {
        private val pending = ByteArrayOutputStream()

        override fun write(b: Int) { pending.write(b) }
        override fun write(b: ByteArray, off: Int, len: Int) { pending.write(b, off, len) }

        override fun flush() {
            if (closed) throw IOException("relay stream closed")
            val bytes = pending.toByteArray()
            pending.reset()
            var off = 0
            while (off < bytes.size) {
                val end = minOf(bytes.size, off + CHUNK)
                if (!send(bytes.copyOfRange(off, end), false)) throw IOException("signal is down")
                off = end
            }
        }
    }

    companion object {
        /** Matches the server's limit (server/src/signal/relay.ts RELAY_CHUNK_BYTES). */
        const val CHUNK = 64 * 1024
        private val EOF = ByteArray(0)
    }
}
