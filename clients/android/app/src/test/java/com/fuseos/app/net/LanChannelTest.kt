package com.fuseos.app.net

import com.fuseos.proto.ClipText
import com.fuseos.proto.Envelope
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
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

    private val pool = Executors.newCachedThreadPool()

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
