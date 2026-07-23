package com.fuseos.app.net

import com.fuseos.proto.ClipText
import com.fuseos.proto.Envelope
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.After
import org.junit.Rule
import org.junit.Test
import org.junit.rules.Timeout
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.security.KeyFactory
import java.security.PrivateKey
import java.security.PublicKey
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.X509EncodedKeySpec
import java.util.Base64
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Byte-for-byte regression protection for the LAN wire format.
 *
 * The macOS client is a second, independent implementation of everything below. Nothing
 * negotiates a version, so the only thing keeping the two compatible is that they agree
 * on these exact bytes. A change to the framing, the key derivation or the protobuf
 * encoding is a cross-platform change; this test is here to make it fail loudly on the
 * Android side rather than quietly on someone's desk.
 *
 * The vectors are fixed inputs — fixed P-256 keys, fixed nonces, fixed device ids, a fixed
 * envelope — so they can be pasted into a Swift test and compared directly.
 *
 * If one of these assertions fails, the question is never "update the expected value";
 * it is "has macOS been changed to match?".
 */
class WireFormatTest {

    /** Socket tests fail by hanging; make that a red test rather than a stuck build. */
    @get:Rule
    val timeout: Timeout = Timeout.seconds(60)

    private val pool = Executors.newCachedThreadPool()

    @After
    fun shutdown() {
        pool.shutdownNow()
    }

    private fun ByteArray.hex(): String = joinToString("") { "%02x".format(it) }

    private fun hex(value: String): ByteArray =
        value.chunked(2).map { it.toInt(16).toByte() }.toByteArray()

    private fun privateKey(base64: String): PrivateKey =
        KeyFactory.getInstance("EC")
            .generatePrivate(PKCS8EncodedKeySpec(Base64.getDecoder().decode(base64)))

    private fun publicKey(base64: String): PublicKey =
        KeyFactory.getInstance("EC")
            .generatePublic(X509EncodedKeySpec(Base64.getDecoder().decode(base64)))

    // MARK: - Fixed inputs

    private companion object {
        /** Device A — the lexicographically LOW id, so the side that dials and whose
         *  send key is `fuseos:lan:v1:low-to-high`. */
        const val ID_A = "aaaa-1111"
        const val ID_B = "bbbb-2222"

        // A throwaway P-256 pair per device. Fixed so the ECDH secret, and therefore the
        // session keys below, are reproducible on any machine and in any language.
        const val PRIVATE_A =
            "MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgKFgjbMoidvK8KHevSQsBRwvDZNIs" +
                "3IZY7xhH6E8P0N+hRANCAASEy/cxOIAEHvclBeTSksCGbG/DviZPFpKLTZ5slYAwzbc8hYRJPJ6U" +
                "/gu+Q8H7LBIerxWRNfgbxSlhE2kBFvgy"
        const val PUBLIC_A =
            "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEhMv3MTiABB73JQXk0pLAhmxvw74mTxaSi02ebJWA" +
                "MM23PIWESTyelP4LvkPB+ywSHq8VkTX4G8UpYRNpARb4Mg=="
        const val PRIVATE_B =
            "MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgPu++Z0YtKFYz9bdlGPEUxzVFi6hL" +
                "4ZISuravkAM7KXuhRANCAAT/uEjYAhOmg0CJ8MSuO4OZy7irsucZ+advc26dZfmLkppz5YkMrCKq" +
                "vtSGKWMR5XlpuXVpQi67Z8SBWc22x8TP"
        const val PUBLIC_B =
            "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE/7hI2AITpoNAifDErjuDmcu4q7LnGfmnb3NunWX5" +
                "i5Kac+WJDKwiqr7UhiljEeV5abl1aUIuu2fEgVnNtsfEzw=="

        /** A's handshake nonce: bytes 0x00…0x1f. */
        const val NONCE_A_HEX = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"

        /** B's handshake nonce: bytes 0xff…0xe0. */
        const val NONCE_B_HEX = "fffefdfcfbfaf9f8f7f6f5f4f3f2f1f0efeeedecebeae9e8e7e6e5e4e3e2e1e0"

        // ---- Pinned outputs. Cross-check every one of these against the Swift client. ----

        /** `[2-byte BE id length]["aaaa-1111"]["0x00…0x1f"]` — 43 bytes. */
        const val HANDSHAKE_A_HEX =
            "0009616161612d31313131" + NONCE_A_HEX

        /** The same for B. */
        const val HANDSHAKE_B_HEX =
            "0009626262622d32323232" + NONCE_B_HEX

        /** `Envelope{ source="aaaa-1111", seq=7, sent_at=1700000000000, ClipText("hello") }`. */
        const val ENVELOPE_HEX =
            "0a09616161612d3131313110071880d095ffbc3152070a0568656c6c6f"

        /** ECDH(A, B) → HKDF, salted with nonceA||nonceB (A is the low id). */
        const val KEY_LOW_TO_HIGH_HEX =
            "cf74a94a7866a9789b1ab5e8c82a91c0883db5cebd5bb4e01231624bbc9e9328"
        const val KEY_HIGH_TO_LOW_HEX =
            "fb90c855dc3eee0c98b8c2ba8d2a6e8b237d6b4b7e5eaebdf1d8b6c7e782b925"

        /** `seal(key = 0x00…0x1f, counter = 0, plaintext = ENVELOPE)` — deterministic,
         *  because AES-GCM's nonce here is the frame counter. */
        const val SEALED_FIXED_KEY_HEX =
            "04b5d4bfd44dae8c399998251f34114947bcea627a866a2ae8fbdfefaadd2c01" +
                "2ffb3acccd9c22e364a4cc4561"

        /** The complete frame A puts on the wire for that envelope as its first frame:
         *  `[4-byte BE length][ciphertext||tag]`, sealed under KEY_LOW_TO_HIGH at counter 0. */
        const val FRAME_A_FIRST_HEX =
            "0000002d" +
                "f7f176472e1c4f2bc82370cdbbdca5a0d33887b889c1ec6ece0299f28440d937" +
                "3cf0b89c549e0ccbe36a7afc78"
    }

    private fun fixedEnvelope(): Envelope =
        Envelope.newBuilder()
            .setSourceDeviceId(ID_A)
            .setSeq(7)
            .setSentAtUnixMs(1_700_000_000_000)
            .setClipText(ClipText.newBuilder().setText("hello"))
            .build()

    // MARK: - Tests

    @Test
    fun `envelope serialisation is stable`() {
        // protobuf field order is not guaranteed by the spec, only by the implementation.
        // Pinning it here means a protobuf-lite upgrade that reorders fields shows up as a
        // test failure rather than as a macOS client that cannot parse an Android frame.
        println("ENVELOPE_HEX = ${fixedEnvelope().toByteArray().hex()}")
        assertEquals(ENVELOPE_HEX, fixedEnvelope().toByteArray().hex())
    }

    @Test
    fun `session key derivation is pinned to fixed keys and nonces`() {
        // The whole chain — ECDH over the static P-256 keys, HKDF-SHA256 salted with the
        // two nonces in device-id order, split by direction. CryptoKit must reproduce
        // these exact 32 bytes or nothing decrypts across platforms.
        val aKeys = LanCrypto.sessionKeys(
            privateKey = privateKey(PRIVATE_A), peerPublicKey = publicKey(PUBLIC_B),
            selfDeviceId = ID_A, peerDeviceId = ID_B,
            selfNonce = hex(NONCE_A_HEX), peerNonce = hex(NONCE_B_HEX),
        )
        val bKeys = LanCrypto.sessionKeys(
            privateKey = privateKey(PRIVATE_B), peerPublicKey = publicKey(PUBLIC_A),
            selfDeviceId = ID_B, peerDeviceId = ID_A,
            selfNonce = hex(NONCE_B_HEX), peerNonce = hex(NONCE_A_HEX),
        )
        println("KEY_LOW_TO_HIGH_HEX = ${aKeys.send.hex()}")
        println("KEY_HIGH_TO_LOW_HEX = ${aKeys.receive.hex()}")

        assertEquals(KEY_LOW_TO_HIGH_HEX, aKeys.send.hex())
        assertEquals(KEY_HIGH_TO_LOW_HEX, aKeys.receive.hex())
        assertEquals(KEY_LOW_TO_HIGH_HEX, bKeys.receive.hex())
        assertEquals(KEY_HIGH_TO_LOW_HEX, bKeys.send.hex())
    }

    @Test
    fun `sealing is pinned for a fixed key and counter`() {
        // AES-GCM with a counter-derived nonce is fully deterministic, so this is a
        // complete vector: it pins the 12-byte nonce layout, the 128-bit tag length and
        // the tag's position at the end of the frame all at once.
        val sealed = LanCrypto.seal(hex(NONCE_A_HEX), 0, hex(ENVELOPE_HEX))
        println("SEALED_FIXED_KEY_HEX = ${sealed.hex()}")
        assertEquals(SEALED_FIXED_KEY_HEX, sealed.hex())
        assertEquals("plaintext plus a 16-byte tag", ENVELOPE_HEX.length / 2 + 16, sealed.size)
    }

    @Test
    fun `handshake bytes on the wire match the pinned layout`() {
        // Read from a real handshake rather than reconstructed here — a test that rebuilds
        // the format it is checking can never catch a change to it. Only the random nonce
        // is substituted, because that is the one part that cannot be pinned.
        val emitted = captureHandshake(ID_A, privateKey(PRIVATE_A), publicKey(PUBLIC_B))
        assertEquals("handshake is 2 + 9 + 32 bytes", 43, emitted.size)

        val withFixedNonce = emitted.copyOf()
        hex(NONCE_A_HEX).copyInto(withFixedNonce, 11)
        println("HANDSHAKE_A_HEX = ${withFixedNonce.hex()}")
        assertEquals(HANDSHAKE_A_HEX, withFixedNonce.hex())
    }

    @Test
    fun `the first frame on the wire matches the pinned layout end to end`() {
        // Everything at once, over a real socket: A's handshake, the derived low-to-high
        // key, the 4-byte big-endian length prefix, the frame counter starting at zero,
        // and the serialised envelope as the plaintext.
        val frame = captureFirstFrame()
        println("FRAME_A_FIRST_HEX = ${frame.hex()}")
        assertEquals(FRAME_A_FIRST_HEX, frame.hex())

        // And the reverse direction: bytes pinned above, fed in, must parse back.
        assertEquals(fixedEnvelope(), Envelope.parseFrom(hex(ENVELOPE_HEX)))
    }

    @Test
    fun `both handshakes are pinned so either side can be the reference`() {
        val emitted = captureHandshake(ID_B, privateKey(PRIVATE_B), publicKey(PUBLIC_A))
        val withFixedNonce = emitted.copyOf()
        hex(NONCE_B_HEX).copyInto(withFixedNonce, 11)
        assertEquals(HANDSHAKE_B_HEX, withFixedNonce.hex())
    }

    // MARK: - Wire capture helpers

    /**
     * Runs a real [LanChannel] handshake against a hand-written peer and hands [block] the
     * raw socket, so a test sees exactly the bytes that go over the wire.
     */
    private fun <T> withRawPeer(
        selfId: String,
        self: PrivateKey,
        peerId: String,
        peerNonce: ByteArray,
        peerPublic: PublicKey,
        block: (DataInputStream, DataOutputStream, () -> LanChannel) -> T,
    ): T {
        val listener = ServerSocket()
        listener.bind(InetSocketAddress(InetAddress.getLoopbackAddress(), 0))
        val channelFuture = pool.submit<LanChannel> {
            listener.use { LanChannel.handshake(it.accept(), selfId, self) { peerPublic } }
        }
        val socket = Socket()
        socket.connect(InetSocketAddress(InetAddress.getLoopbackAddress(), listener.localPort))
        return socket.use {
            val input = DataInputStream(it.getInputStream())
            val output = DataOutputStream(it.getOutputStream())
            // Answer first: both sides write before reading, so blocking here deadlocks.
            output.writeShort(peerId.toByteArray(Charsets.UTF_8).size)
            output.write(peerId.toByteArray(Charsets.UTF_8))
            output.write(peerNonce)
            output.flush()
            try {
                block(input, output) { channelFuture.get(10, TimeUnit.SECONDS) }
            } finally {
                runCatching { channelFuture.get(10, TimeUnit.SECONDS).close() }
            }
        }
    }

    /** Returns the exact 43 handshake bytes [selfId] put on the wire. */
    private fun captureHandshake(selfId: String, self: PrivateKey, peer: PublicKey): ByteArray {
        val (peerId, peerNonce) =
            if (selfId == ID_A) ID_B to hex(NONCE_B_HEX) else ID_A to hex(NONCE_A_HEX)
        return withRawPeer(selfId, self, peerId, peerNonce, peer) { input, _, _ ->
            ByteArray(43).also { input.readFully(it) }
        }
    }

    /**
     * Drives a real handshake as A, captures the complete first frame A sends, and
     * rebuilds it under the pinned nonce so the result is reproducible.
     *
     * A's own nonce is random — that is the point of a nonce — so the frame A actually
     * emits cannot be pinned directly. Instead this proves the real frame decrypts with
     * the real derived key at counter 0, then re-seals the same envelope under the pinned
     * key to produce the vector Swift can compare against.
     */
    private fun captureFirstFrame(): ByteArray =
        withRawPeer(ID_A, privateKey(PRIVATE_A), ID_B, hex(NONCE_B_HEX), publicKey(PUBLIC_B)) {
                input, _, channel ->
            val handshake = ByteArray(43).also { input.readFully(it) }
            val aNonce = handshake.copyOfRange(11, 43)

            channel().send(fixedEnvelope())

            val length = input.readInt()
            val ciphertext = ByteArray(length).also { input.readFully(it) }

            val realKey = LanCrypto.sessionKeys(
                privateKey = privateKey(PRIVATE_B), peerPublicKey = publicKey(PUBLIC_A),
                selfDeviceId = ID_B, peerDeviceId = ID_A,
                selfNonce = hex(NONCE_B_HEX), peerNonce = aNonce,
            ).receive
            assertArrayEquals(
                "the first frame must be the envelope, sealed at counter 0",
                fixedEnvelope().toByteArray(),
                LanCrypto.open(realKey, 0, ciphertext),
            )

            val pinned = LanCrypto.seal(hex(KEY_LOW_TO_HIGH_HEX), 0, fixedEnvelope().toByteArray())
            assertEquals("the length prefix counts the sealed frame", pinned.size, length)
            hex("%08x".format(pinned.size)) + pinned
        }
}
