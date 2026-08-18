import Foundation

/// How far along the connection to a paired peer is.
///
/// The stages are ordered: a device climbs from `notPaired` up to `connected`, and the
/// connect screen shows whichever stage the best peer has reached. Ordering is what lets
/// several paired peers collapse into one screen state — the furthest-along peer wins,
/// because that is the one the user is about to start using.
public enum ConnectStage: Int, Comparable, Sendable {
    /// No paired peers at all — the user still has to scan a code.
    case notPaired = 0
    /// Paired, but the peer isn't running the app right now.
    case peerOffline = 1
    /// Both online, but on different networks, so no LAN channel is possible.
    case differentNetwork = 2
    /// Same network, dialling — this resolves on its own within a few seconds.
    case connecting = 3
    /// A live encrypted LAN channel exists. This is the only stage that can continue.
    case connected = 4

    public static func < (lhs: ConnectStage, rhs: ConnectStage) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct ConnectState: Equatable, Sendable {
    public let stage: ConnectStage
    /// The peer this state describes, or nil at `notPaired`.
    public let peerId: String?
    /// Populated only at `differentNetwork`, so the UI can name both networks.
    public let selfSubnet: String?
    public let peerSubnet: String?

    public init(
        stage: ConnectStage,
        peerId: String? = nil,
        selfSubnet: String? = nil,
        peerSubnet: String? = nil,
    ) {
        self.stage = stage
        self.peerId = peerId
        self.selfSubnet = selfSubnet
        self.peerSubnet = peerSubnet
    }
}

public enum ConnectStateEvaluator {
    /// The IPv4 /24 an `ip:port` sits on, or nil if it isn't a dotted-quad.
    ///
    /// A /24 is an assumption, not a fact — it is the netmask behind essentially every
    /// consumer router and phone hotspot, and we have no way to learn the real one from a
    /// peer's advertised address. Getting it wrong only ever mislabels the *reason* on
    /// screen; `connected` is still decided by a real channel existing, never by this.
    public static func subnet(of address: String) -> String? {
        let host = address.split(separator: ":").first.map(String.init) ?? address
        let octets = host.split(separator: ".")
        guard octets.count == 4, octets.allSatisfy({ UInt8($0) != nil }) else { return nil }
        return octets.prefix(3).joined(separator: ".")
    }

    /// Collapses the device roster into the single state the connect screen renders.
    ///
    /// Pure and platform-free so both clients can agree on what "connected" means, and so
    /// the ordering rules are testable without a second physical device.
    public static func evaluate(
        selfLanAddress: String?,
        peerIds: [String],
        presence: [String: PeerPresence],
        connected: Set<String>,
    ) -> ConnectState {
        var best = ConnectState(stage: .notPaired)
        for peerId in peerIds {
            let candidate = evaluate(
                peerId: peerId,
                selfLanAddress: selfLanAddress,
                presence: presence[peerId],
                isConnected: connected.contains(peerId),
            )
            if candidate.stage >= best.stage { best = candidate }
        }
        return best
    }

    private static func evaluate(
        peerId: String,
        selfLanAddress: String?,
        presence: PeerPresence?,
        isConnected: Bool,
    ) -> ConnectState {
        // A live channel outranks everything. Presence arrives over the control plane and
        // can lag or be stale; the channel is ground truth, so it is checked first.
        if isConnected { return ConnectState(stage: .connected, peerId: peerId) }
        guard let presence, presence.online else {
            return ConnectState(stage: .peerOffline, peerId: peerId)
        }
        guard
            let selfSubnet = selfLanAddress.flatMap(subnet(of:)),
            let peerSubnet = presence.lanAddress.flatMap(subnet(of:))
        else {
            // Either side may not have bound its listener yet. That is a normal few-hundred
            // milliseconds at launch, not a network problem, so it reads as "connecting"
            // rather than accusing the user of being on the wrong WiFi.
            return ConnectState(stage: .connecting, peerId: peerId)
        }
        guard selfSubnet == peerSubnet else {
            return ConnectState(
                stage: .differentNetwork,
                peerId: peerId,
                selfSubnet: selfSubnet,
                peerSubnet: peerSubnet,
            )
        }
        return ConnectState(stage: .connecting, peerId: peerId)
    }
}
