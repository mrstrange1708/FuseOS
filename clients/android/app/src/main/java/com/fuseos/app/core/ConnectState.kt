package com.fuseos.app.core

import com.fuseos.app.data.PeerPresence

/**
 * How far along the connection to the account's other device is.
 *
 * The stages are ordered: a device climbs from [Alone] up to [Connected], and the
 * connect screen shows whichever stage the best peer has reached. Ordering is what lets
 * several peers collapse into one screen state — the furthest-along peer wins,
 * because that is the one the user is about to start using.
 *
 * Mirrors `ConnectState.swift` on macOS; the two must agree on what "connected" means.
 */
enum class ConnectStage {
    /** This account has no other device yet — the user has to sign in on one. */
    Alone,

    /** There is another device on the account, but it isn't running the app right now. */
    PeerOffline,

    /** Both online, but on different networks, so no LAN channel is possible. */
    DifferentNetwork,

    /** Same network, dialling — this resolves on its own within a few seconds. */
    Connecting,

    /** A live encrypted LAN channel exists. This is the only stage that can continue. */
    Connected,
}

data class ConnectState(
    val stage: ConnectStage,
    /** The peer this state describes, or null at [ConnectStage.Alone]. */
    val peerId: String? = null,
    /** Populated only at [ConnectStage.DifferentNetwork], so the UI can name both networks. */
    val selfSubnet: String? = null,
    val peerSubnet: String? = null,
)

object ConnectStateEvaluator {
    /**
     * The IPv4 /24 an `ip:port` sits on, or null if it isn't a dotted-quad.
     *
     * A /24 is an assumption, not a fact — it is the netmask behind essentially every
     * consumer router and phone hotspot, and we have no way to learn the real one from a
     * peer's advertised address. Getting it wrong only ever mislabels the *reason* on
     * screen; [ConnectStage.Connected] is still decided by a real channel existing.
     */
    fun subnet(address: String): String? {
        val host = address.substringBefore(':')
        val octets = host.split('.')
        if (octets.size != 4 || octets.any { it.toIntOrNull()?.takeIf { n -> n in 0..255 } == null }) {
            return null
        }
        return octets.take(3).joinToString(".")
    }

    /**
     * Collapses the device roster into the single state the connect screen renders.
     *
     * Pure and Android-free so both clients agree on the rules, and so the ordering is
     * testable without a second physical device.
     */
    fun evaluate(
        selfLanAddress: String?,
        peerIds: List<String>,
        presence: Map<String, PeerPresence>,
        connected: Set<String>,
    ): ConnectState {
        var best = ConnectState(ConnectStage.Alone)
        for (peerId in peerIds) {
            val candidate = evaluatePeer(
                peerId = peerId,
                selfLanAddress = selfLanAddress,
                presence = presence[peerId],
                isConnected = peerId in connected,
            )
            if (candidate.stage >= best.stage) best = candidate
        }
        return best
    }

    private fun evaluatePeer(
        peerId: String,
        selfLanAddress: String?,
        presence: PeerPresence?,
        isConnected: Boolean,
    ): ConnectState {
        // A live channel outranks everything. Presence arrives over the control plane and
        // can lag or be stale; the channel is ground truth, so it is checked first.
        if (isConnected) return ConnectState(ConnectStage.Connected, peerId)
        if (presence == null || !presence.online) {
            return ConnectState(ConnectStage.PeerOffline, peerId)
        }
        val selfSubnet = selfLanAddress?.let { subnet(it) }
        val peerSubnet = presence.lanAddress?.let { subnet(it) }
        // Either side may not have bound its listener yet. That is a normal few-hundred
        // milliseconds at launch, not a network problem, so it reads as "connecting"
        // rather than accusing the user of being on the wrong WiFi.
        if (selfSubnet == null || peerSubnet == null) {
            return ConnectState(ConnectStage.Connecting, peerId)
        }
        if (selfSubnet != peerSubnet) {
            return ConnectState(ConnectStage.DifferentNetwork, peerId, selfSubnet, peerSubnet)
        }
        return ConnectState(ConnectStage.Connecting, peerId)
    }
}
