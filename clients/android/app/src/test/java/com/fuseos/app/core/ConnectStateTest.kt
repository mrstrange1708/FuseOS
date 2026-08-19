package com.fuseos.app.core

import com.fuseos.app.data.PeerPresence
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The connect screen is the one place a user is told *why* two devices aren't talking,
 * so the stage each situation maps to is behaviour, not presentation.
 *
 * Mirrors `ConnectStateTests.swift` case for case: if one platform's rules change without
 * the other's, one of these two suites fails.
 */
class ConnectStateTest {
    private fun presence(online: Boolean, lan: String?) =
        PeerPresence(online = online, battery = null, publicKey = null, lanAddress = lan)

    private fun evaluate(
        selfLan: String?,
        peers: Map<String, PeerPresence>,
        connected: Set<String> = emptySet(),
    ) = ConnectStateEvaluator.evaluate(
        selfLanAddress = selfLan,
        peerIds = peers.keys.sorted(),
        presence = peers,
        connected = connected,
    )

    @Test
    fun `no other devices on the account is alone`() {
        assertEquals(
            ConnectStage.Alone,
            evaluate("192.168.1.5:9000", emptyMap()).stage,
        )
    }

    @Test
    fun `peer on the account but offline`() {
        val state = evaluate("192.168.1.5:9000", mapOf("b" to presence(false, null)))
        assertEquals(ConnectStage.PeerOffline, state.stage)
        assertEquals("b", state.peerId)
    }

    @Test
    fun `online peer on another subnet reports both networks`() {
        val state = evaluate(
            "192.168.1.5:9000",
            mapOf("b" to presence(true, "10.171.188.173:41234")),
        )
        assertEquals(ConnectStage.DifferentNetwork, state.stage)
        assertEquals("192.168.1", state.selfSubnet)
        assertEquals("10.171.188", state.peerSubnet)
    }

    @Test
    fun `same subnet without channel is connecting`() {
        val state = evaluate(
            "192.168.43.24:9000",
            mapOf("b" to presence(true, "192.168.43.1:41234")),
        )
        assertEquals(ConnectStage.Connecting, state.stage)
    }

    /** A listener that hasn't bound yet is a normal launch race, not a wrong-network error. */
    @Test
    fun `missing lan address is connecting not different network`() {
        val state = evaluate(null, mapOf("b" to presence(true, null)))
        assertEquals(ConnectStage.Connecting, state.stage)
    }

    /**
     * The channel is ground truth: presence may be stale or absent, but if bytes flow, we
     * are connected. Continue must never be withheld from a peer we can actually reach.
     */
    @Test
    fun `live channel outranks stale presence`() {
        val state = evaluate(
            "192.168.1.5:9000",
            mapOf("b" to presence(false, null)),
            connected = setOf("b"),
        )
        assertEquals(ConnectStage.Connected, state.stage)
        assertEquals("b", state.peerId)
    }

    /**
     * With several devices the screen follows the furthest-along one, so one
     * offline laptop cannot mask a phone that is ready to use.
     */
    @Test
    fun `furthest along peer wins`() {
        val state = evaluate(
            "192.168.1.5:9000",
            mapOf(
                "a" to presence(false, null),
                "z" to presence(true, "192.168.1.9:41234"),
            ),
            connected = setOf("z"),
        )
        assertEquals(ConnectStage.Connected, state.stage)
        assertEquals("z", state.peerId)
    }

    @Test
    fun `subnet parsing rejects non dotted quads`() {
        assertEquals("192.168.1", ConnectStateEvaluator.subnet("192.168.1.5:9000"))
        assertNull(ConnectStateEvaluator.subnet("fe80::1:9000"))
        assertNull(ConnectStateEvaluator.subnet("999.1.1.1:9000"))
        assertNull(ConnectStateEvaluator.subnet("hostname:9000"))
    }
}
