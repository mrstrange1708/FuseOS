package com.fuseos.app.net

import com.fuseos.proto.Envelope
import java.io.Closeable
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.Socket
import java.security.GeneralSecurityException
import java.security.PrivateKey
import java.security.PublicKey
import java.security.SecureRandom

/**
 * One authenticated, encrypted connection to a paired device. The macOS `LanChannel` is
 * the mirror of this file — the wire format below is the contract between them.
 *
 * ```
 * handshake, plaintext, once:  [2-byte BE id length][device id UTF-8][32-byte nonce]
 * every frame after:           [4-byte BE length][AES-GCM ciphertext || 16-byte tag]
 * ```
 *
 * The handshake carries a device id because the listening side sees only an IP address,
 * and the id is what lets it look up the public key the control plane vouched for. A
 * peer whose key we do not hold is not a peer, and the socket closes. Nothing is
 * decrypted before that check, so an unknown caller can never reach the envelope layer.
 */
class LanChannel private constructor(
    private val socket: Socket,
    private val keys: LanCrypto.SessionKeys,
    val peerDeviceId: String,
) : Closeable {

    private val input = DataInputStream(socket.getInputStream().buffered())
    private val output = DataOutputStream(socket.getOutputStream().buffered())

    // Frame counters double as the GCM nonces, so they must move in lockstep with the
    // peer's. TCP guarantees the ordering that keeps them aligned.
    private var sendCounter = 0L
    private var receiveCounter = 0L

    private val sendLock = Any()

    /** Blocking. Safe to call from multiple threads; frames are serialised. */
    fun send(envelope: Envelope): Unit = synchronized(sendLock) {
        val frame = LanCrypto.seal(keys.send, sendCounter++, envelope.toByteArray())
        output.writeInt(frame.size)
        output.write(frame)
        output.flush()
    }

    /**
     * Blocking read of the next envelope. Throws at end of stream, on a malformed length,
     * or when the tag check fails — all of which mean this connection is finished.
     */
    fun receive(): Envelope {
        val length = input.readInt()
        if (length !in 1..MAX_FRAME_BYTES) {
            throw GeneralSecurityException("frame length $length out of range")
        }
        val frame = ByteArray(length)
        input.readFully(frame)
        return Envelope.parseFrom(LanCrypto.open(keys.receive, receiveCounter++, frame))
    }

    override fun close() {
        runCatching { socket.close() }
    }

    companion object {
        /** Bounds what a peer can make us allocate from a single length prefix. */
        private const val MAX_FRAME_BYTES = 4 * 1024 * 1024
        private const val MAX_DEVICE_ID_BYTES = 128

        /**
         * Performs the handshake on an already-connected socket, in whichever direction.
         *
         * [trustedKeyFor] returns a peer's public key only if that peer is genuinely
         * paired with this device — returning null is what rejects a stranger.
         */
        fun handshake(
            socket: Socket,
            selfDeviceId: String,
            privateKey: PrivateKey,
            trustedKeyFor: (String) -> PublicKey?,
        ): LanChannel {
            // Deliberately unbuffered: these read exact byte counts and must not consume
            // any of the framed traffic that follows.
            val input = DataInputStream(socket.getInputStream())
            val output = DataOutputStream(socket.getOutputStream())

            val selfNonce = ByteArray(LanCrypto.NONCE_LEN).also { SecureRandom().nextBytes(it) }
            val selfId = selfDeviceId.toByteArray(Charsets.UTF_8)
            output.writeShort(selfId.size)
            output.write(selfId)
            output.write(selfNonce)
            output.flush()

            val peerIdLength = input.readUnsignedShort()
            if (peerIdLength !in 1..MAX_DEVICE_ID_BYTES) {
                throw GeneralSecurityException("device id length $peerIdLength out of range")
            }
            val peerId = ByteArray(peerIdLength)
                .also { input.readFully(it) }
                .toString(Charsets.UTF_8)
            val peerNonce = ByteArray(LanCrypto.NONCE_LEN).also { input.readFully(it) }

            if (peerId == selfDeviceId) {
                throw GeneralSecurityException("refusing to connect to self")
            }
            val peerKey = trustedKeyFor(peerId)
                ?: throw GeneralSecurityException("no trusted key for peer $peerId")

            val keys = LanCrypto.sessionKeys(
                privateKey = privateKey,
                peerPublicKey = peerKey,
                selfDeviceId = selfDeviceId,
                peerDeviceId = peerId,
                selfNonce = selfNonce,
                peerNonce = peerNonce,
            )
            return LanChannel(socket, keys, peerId)
        }
    }
}
