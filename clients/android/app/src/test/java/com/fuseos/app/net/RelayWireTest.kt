package com.fuseos.app.net

import com.fuseos.proto.ClipText
import com.fuseos.proto.Envelope
import com.fuseos.proto.FileChunk
import com.google.protobuf.ByteString
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.Timeout
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.spec.ECGenParameterSpec
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** The same channel — handshake, keys, sealed frames — over the relay's message pieces. */
class RelayWireTest {
    @get:Rule
    val timeout: Timeout = Timeout.seconds(60)

    private val pool = Executors.newCachedThreadPool()

    @After
    fun shutdown() {
        pool.shutdownNow()
    }

    private fun keyPair(): KeyPair =
        KeyPairGenerator.getInstance("EC").apply { initialize(ECGenParameterSpec("secp256r1")) }.generateKeyPair()

    /** Two wires joined as the server joins them: one's pieces are the other's input. */
    private fun relayPair(): Pair<RelayWire, RelayWire> {
        lateinit var a: RelayWire
        lateinit var b: RelayWire
        var pieces = 0
        a = RelayWire("b", "s") { data, close -> if (close) b.end() else b.deliver(data!!).also { pieces++ }; true }
        b = RelayWire("a", "s") { data, close -> if (close) a.end() else a.deliver(data!!); true }
        return a to b
    }

    @Test
    fun `a sealed channel runs over relay pieces, big frames split and rejoined`() {
        val ka = keyPair()
        val kb = keyPair()
        val (wa, wb) = relayPair()
        val accepted = pool.submit<LanChannel> { LanChannel.handshake(wb, "bbbb", kb.private) { ka.public } }
        val dialed = pool.submit<LanChannel> { LanChannel.handshake(wa, "aaaa", ka.private) { kb.public } }
        val alice = dialed.get(10, TimeUnit.SECONDS)
        val bob = accepted.get(10, TimeUnit.SECONDS)
        assertTrue(alice.viaRelay && bob.viaRelay)

        alice.send(Envelope.newBuilder().setClipText(ClipText.newBuilder().setText("over the relay")).build())
        assertEquals("over the relay", bob.receive().clipText.text)

        // Bigger than one 64 KB relay piece: split on the way, whole on arrival.
        val big = ByteArray(200 * 1024) { it.toByte() }
        bob.send(Envelope.newBuilder().setFileChunk(FileChunk.newBuilder().setData(ByteString.copyFrom(big))).build())
        assertEquals(ByteString.copyFrom(big), alice.receive().fileChunk.data)

        alice.close()
        assertTrue(runCatching { bob.receive() }.isFailure) // the close reaches the other end
    }

    @Test
    fun `the relay carries copies and commands, not files, mirroring or history`() {
        fun env(build: Envelope.Builder.() -> Unit) = Envelope.newBuilder().apply(build).build()
        assertTrue(Relay.carries(env { clipText = ClipText.newBuilder().setText("hi").build() }))
        assertFalse(Relay.carries(env { fileChunk = FileChunk.getDefaultInstance() }))
        assertFalse(Relay.carries(env { setScreenFrame(com.fuseos.proto.ScreenFrame.getDefaultInstance()) }))
        assertFalse(Relay.carries(env { setHistorySync(com.fuseos.proto.HistorySync.getDefaultInstance()) }))
    }
}
