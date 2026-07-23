package com.fuseos.app.net

import com.fuseos.proto.ClipText
import com.fuseos.proto.Envelope
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
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
import java.security.GeneralSecurityException
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.PublicKey
import java.security.spec.ECGenParameterSpec
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Exercises the real handshake and framing over a loopback socket.
 *
 * This is the code two physical devices depend on, and the failure modes are silent —
 * a mismatched counter or a wrong length prefix deadlocks rather than throwing
 * somewhere obvious. Verifying the full round trip in-process is what makes the
 * on-device test a confirmation instead of a debugging session.
 *
 * The peer here is a second keypair, exactly as a paired device would be.
 */
class LanChannelTest {

    /**
     * Socket tests fail by hanging, not by throwing — a mismatched frame length or a
     * missing reader just blocks forever. A hard ceiling turns that into a red test
     * instead of a stuck build.
     */
    @get:Rule
    val timeout: Timeout = Timeout.seconds(120)

    private val pool = Executors.newCachedThreadPool()

    @After
    fun shutdown() {
        pool.shutdownNow()
    }

    private fun keyPair(): KeyPair =
        KeyPairGenerator.getInstance("EC")
            .apply { initialize(ECGenParameterSpec("secp256r1")) }
            .generateKeyPair()

    /** Connects two channels over loopback, running each handshake concurrently. */
    private fun connect(
        aId: String,
        bId: String,
        aKeys: KeyPair,
        bKeys: KeyPair,
        aTrusts: (String) -> PublicKey?,
        bTrusts: (String) -> PublicKey?,
    ): Pair<LanChannel, LanChannel> {
        ServerSocket().use { listener ->
            listener.bind(InetSocketAddress(InetAddress.getLoopbackAddress(), 0))

            // Both sides write before reading, so they must run at the same time.
            val accepted = pool.submit<LanChannel> {
                LanChannel.handshake(listener.accept(), bId, bKeys.private, bTrusts)
            }
            val dialed = pool.submit<LanChannel> {
                val socket = Socket()
                socket.connect(InetSocketAddress(InetAddress.getLoopbackAddress(), listener.localPort))
                LanChannel.handshake(socket, aId, aKeys.private, aTrusts)
            }
            return dialed.get(10, TimeUnit.SECONDS) to accepted.get(10, TimeUnit.SECONDS)
        }
    }

    private fun clip(text: String): Envelope =
        Envelope.newBuilder()
            .setSourceDeviceId("sender")
            .setSeq(1)
            .setSentAtUnixMs(0)
            .setClipText(ClipText.newBuilder().setText(text))
            .build()

    @Test
    fun `paired devices exchange envelopes in both directions`() {
        val a = keyPair()
        val b = keyPair()
        val (aChannel, bChannel) = connect(
            aId = "aaaa-1111", bId = "bbbb-2222", aKeys = a, bKeys = b,
            aTrusts = { b.public }, bTrusts = { a.public },
        )

        aChannel.use { alice ->
            bChannel.use { bob ->
                assertEquals("bbbb-2222", alice.peerDeviceId)
                assertEquals("aaaa-1111", bob.peerDeviceId)

                alice.send(clip("copied on A"))
                assertEquals("copied on A", bob.receive().clipText.text)

                bob.send(clip("copied on B"))
                assertEquals("copied on B", alice.receive().clipText.text)

                // Several frames in a row: the GCM counters only stay aligned if both
                // sides advance in lockstep, so a drift shows up here and nowhere else.
                repeat(5) { i -> alice.send(clip("frame $i")) }
                repeat(5) { i -> assertEquals("frame $i", bob.receive().clipText.text) }
            }
        }
    }

    @Test
    fun `a peer we hold no key for is rejected before any payload`() {
        val a = keyPair()
        val b = keyPair()
        try {
            // B is paired with A, but A has never heard of B.
            val (aChannel, bChannel) = connect(
                aId = "aaaa-1111", bId = "bbbb-2222", aKeys = a, bKeys = b,
                aTrusts = { null }, bTrusts = { a.public },
            )
            aChannel.close()
            bChannel.close()
            fail("handshake should have refused a peer with no trusted key")
        } catch (e: Exception) {
            val cause = generateSequence(e as Throwable) { it.cause }
                .firstOrNull { it is GeneralSecurityException }
            assertTrue("expected a security failure, got $e", cause != null)
        }
    }

    // MARK: - Framing limits
    //
    // The 4-byte length prefix is attacker-controlled: it arrives before anything is
    // authenticated, and whatever it says is what we allocate. These cases go through a
    // hand-written peer rather than a second LanChannel, because a LanChannel can never
    // emit a malformed frame — only a hostile or broken implementation can.

    /**
     * A peer that speaks the wire format by hand, so a test can send bytes a well-behaved
     * [LanChannel] would refuse to produce. Mirrors what the macOS client must send.
     */
    private class RawPeer(val socket: Socket) : AutoCloseable {
        val input = DataInputStream(socket.getInputStream())
        val output = DataOutputStream(socket.getOutputStream())

        /** Sends our half of the handshake and reads theirs; returns the peer's nonce. */
        fun handshake(deviceId: String, nonce: ByteArray = ByteArray(32) { 9 }): Pair<String, ByteArray> {
            val id = deviceId.toByteArray(Charsets.UTF_8)
            output.writeShort(id.size)
            output.write(id)
            output.write(nonce)
            output.flush()
            return readPeerHandshake()
        }

        /** Sends a deliberately illegal device id length and nothing else. */
        fun sendBadIdLength(length: Int) {
            output.writeShort(length)
            output.flush()
        }

        fun readPeerHandshake(): Pair<String, ByteArray> {
            val length = input.readUnsignedShort()
            val id = ByteArray(length).also { input.readFully(it) }.toString(Charsets.UTF_8)
            val peerNonce = ByteArray(32).also { input.readFully(it) }
            return id to peerNonce
        }

        fun sendRawLength(length: Int) {
            output.writeInt(length)
            output.flush()
        }

        override fun close() {
            runCatching { socket.close() }
        }
    }

    /**
     * Connects a real [LanChannel] (as the accepting side) to a [RawPeer]. Returns both
     * so a test can drive bytes at the channel directly.
     */
    private fun connectRaw(
        selfId: String,
        selfKeys: KeyPair,
        trusts: (String) -> PublicKey?,
    ): Pair<java.util.concurrent.Future<LanChannel>, RawPeer> {
        val listener = ServerSocket()
        listener.bind(InetSocketAddress(InetAddress.getLoopbackAddress(), 0))
        val accepted = pool.submit<LanChannel> {
            listener.use { LanChannel.handshake(it.accept(), selfId, selfKeys.private, trusts) }
        }
        val socket = Socket()
        socket.connect(InetSocketAddress(InetAddress.getLoopbackAddress(), listener.localPort))
        return accepted to RawPeer(socket)
    }

    private fun assertSecurityFailure(block: () -> Unit) {
        try {
            block()
            fail("expected the connection to be refused")
        } catch (e: Exception) {
            val cause = generateSequence(e as Throwable) { it.cause }
                .firstOrNull { it is GeneralSecurityException }
            assertTrue("expected a security failure, got $e", cause != null)
        }
    }

    @Test
    fun `a frame length prefix outside the allowed range is refused`() {
        val a = keyPair()
        val b = keyPair()
        // A negative prefix would index backwards; zero would spin; anything above the cap
        // is a one-packet out-of-memory kill on a phone. All three must throw, not allocate.
        // 1..15 are the subtle ones: they pass a naive "greater than zero" guard but are
        // too short to hold a GCM tag, and the cipher then throws an unchecked
        // ProviderException instead of the GeneralSecurityException this method documents.
        for (badLength in listOf(-1, Int.MIN_VALUE, 0, 1, 15, 4 * 1024 * 1024 + 1, Int.MAX_VALUE)) {
            val (channelFuture, peer) = connectRaw("bbbb-2222", b) { a.public }
            peer.use {
                it.handshake("aaaa-1111")
                val channel = channelFuture.get(10, TimeUnit.SECONDS)
                channel.use { open ->
                    it.sendRawLength(badLength)
                    try {
                        open.receive()
                        fail("frame length $badLength must be refused")
                    } catch (e: GeneralSecurityException) {
                        assertTrue(e.message!!.contains("$badLength"))
                    }
                }
            }
        }
    }

    @Test
    fun `a frame exactly at the cap passes the length guard`() {
        // Pins the boundary itself: the cap has to be inclusive, or a legal 4 MB frame
        // from macOS would be dropped as hostile.
        val a = keyPair()
        val b = keyPair()
        val (channelFuture, peer) = connectRaw("bbbb-2222", b) { a.public }
        peer.use {
            it.handshake("aaaa-1111")
            val channel = channelFuture.get(10, TimeUnit.SECONDS)
            channel.use { open ->
                // A 4 MB prefix is in range, so it is the tag check that rejects the
                // garbage that follows — not the length guard.
                // Written from another thread: 4 MB is larger than the socket buffer, so
                // writing and reading on one thread would simply deadlock.
                pool.submit<Unit> {
                    it.sendRawLength(4 * 1024 * 1024)
                    it.output.write(ByteArray(4 * 1024 * 1024))
                    it.output.flush()
                }
                try {
                    open.receive()
                    fail("garbage under the cap must still fail its tag check")
                } catch (e: Exception) {
                    assertTrue("expected a tag failure, got $e", e is javax.crypto.AEADBadTagException)
                }
            }
        }
    }

    @Test
    fun `a device id length outside one to 128 is refused`() {
        val a = keyPair()
        val b = keyPair()
        // Zero would mean an anonymous peer; anything large is an allocation the caller
        // chose for us before we know who they are.
        for (badLength in listOf(0, 129, 65_535)) {
            val (channelFuture, peer) = connectRaw("bbbb-2222", b) { a.public }
            peer.use {
                it.sendBadIdLength(badLength)
                assertSecurityFailure { channelFuture.get(10, TimeUnit.SECONDS) }
            }
        }
    }

    @Test
    fun `a peer presenting our own device id is refused`() {
        // Either a misconfigured clone of this device or someone reflecting our handshake
        // back at us. Both would derive keys against our own public key and produce a
        // channel talking to itself.
        val a = keyPair()
        val (channelFuture, peer) = connectRaw("aaaa-1111", a) { a.public }
        peer.use {
            it.handshake("aaaa-1111")
            assertSecurityFailure { channelFuture.get(10, TimeUnit.SECONDS) }
        }
    }

    @Test
    fun `a payload near the frame cap round trips`() {
        // Small frames fit in one TCP segment and never exercise the buffered reader's
        // partial-read path; a megabyte does. This is the size a real screenshot lands at.
        val a = keyPair()
        val b = keyPair()
        val (aChannel, bChannel) = connect(
            aId = "aaaa-1111", bId = "bbbb-2222", aKeys = a, bKeys = b,
            aTrusts = { b.public }, bTrusts = { a.public },
        )
        aChannel.use { alice ->
            bChannel.use { bob ->
                val big = buildString { repeat(1024 * 1024) { append('a' + (it % 26)) } }
                // Send off-thread: a frame this size can exceed the socket buffer, and a
                // blocking write with no concurrent reader would deadlock the test rather
                // than exercise the transport.
                val sent = pool.submit<Unit> { alice.send(clip(big)) }
                assertEquals(big, bob.receive().clipText.text)
                sent.get(30, TimeUnit.SECONDS)
            }
        }
    }

    @Test
    fun `concurrent sends from many threads arrive intact and in counter order`() {
        // send() is synchronized because the frame counter doubles as the GCM nonce: two
        // threads interleaving their writes would desynchronise the counters and every
        // later frame would fail its tag check. Unsynchronised, this test deadlocks or
        // throws rather than merely reordering.
        val a = keyPair()
        val b = keyPair()
        val (aChannel, bChannel) = connect(
            aId = "aaaa-1111", bId = "bbbb-2222", aKeys = a, bKeys = b,
            aTrusts = { b.public }, bTrusts = { a.public },
        )
        aChannel.use { alice ->
            bChannel.use { bob ->
                val total = 100
                val threads = 8
                val next = java.util.concurrent.atomic.AtomicInteger()
                val senders = (0 until threads).map {
                    pool.submit<Unit> {
                        while (true) {
                            val i = next.getAndIncrement()
                            if (i >= total) break
                            alice.send(clip("frame $i"))
                        }
                    }
                }
                val received = mutableListOf<String>()
                repeat(total) { received += bob.receive().clipText.text }
                senders.forEach { it.get(10, TimeUnit.SECONDS) }

                // Every frame decrypted, which is only possible if the counters stayed in
                // lockstep, and none was lost or duplicated.
                assertEquals(
                    (0 until total).map { "frame $it" }.toSet(),
                    received.toSet(),
                )
                assertEquals(total, received.size)
            }
        }
    }

    @Test
    fun `a tampered frame fails its tag check rather than being applied`() {
        val a = keyPair()
        val b = keyPair()
        val keys = LanCrypto.sessionKeys(
            privateKey = a.private, peerPublicKey = b.public,
            selfDeviceId = "aaaa", peerDeviceId = "bbbb",
            selfNonce = ByteArray(32), peerNonce = ByteArray(32) { 1 },
        )
        val sealed = LanCrypto.seal(keys.send, 0, "payload".toByteArray())
        sealed[0] = (sealed[0] + 1).toByte()
        try {
            LanCrypto.open(keys.send, 0, sealed)
            fail("a modified frame must not decrypt")
        } catch (e: Exception) {
            assertTrue(e is javax.crypto.AEADBadTagException)
        }
    }
}
