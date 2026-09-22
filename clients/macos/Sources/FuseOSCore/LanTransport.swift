import CryptoKit
import Foundation
import Network

/// The LAN data plane: direct, encrypted, device-to-device connections to paired peers.
///
/// Nothing here touches the control plane beyond reading presence. Clipboard and file
/// payloads travel over these connections and are never sent to the server — that
/// separation is the architecture's central invariant.
///
/// Discovery is signalling-provided rather than mDNS: `/signal` already relays each peer's
/// `lanAddress` and `publicKey`, which is everything needed to dial and authenticate.
/// ponytail: add Bonjour (`_fuseos._tcp`) when pairing has to work without internet —
/// NWListener advertises it with one extra parameter.
///
/// Every device listens, but only one side dials — the lexicographically lower device id.
/// Without that tie-break both ends dial simultaneously and each pair ends up with two
/// half-used connections.
@MainActor
public final class LanTransport {
    /// Clipboard envelopes received from any peer. Heartbeats are consumed here, not
    /// republished.
    var onEnvelope: ((FuseEnvelope) -> Void)?

    /// File envelopes — meta, chunk, ack. A separate hook rather than one firehose because
    /// `ClipboardSync` and `FileTransfer` want disjoint halves of the protocol, and routing
    /// once here beats each of them filtering out the other's messages.
    var onFileEnvelope: ((FuseEnvelope) -> Void)?

    /// Peers with a live direct channel right now — what the UI's "connected" chip reads.
    public private(set) var connectedPeers: Set<String> = []
    public var onConnectedPeersChanged: ((Set<String>) -> Void)?

    private var listener: NWListener?
    private var selfDeviceId: String?
    private var peers: [String: PeerPresence] = [:]
    private var channels: [String: LanChannel] = [:]
    private var supervisors: [String: Task<Void, Never>] = [:]
    private var acceptTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var sequenceNumber: UInt64 = 0

    /// Identifies this run of the process, so a peer can tell our restarted `seq` counter
    /// from a replay. Minted once per LanTransport rather than per connection: it has to
    /// survive reconnects, or every dropped channel would look like a restart.
    private let sessionId = UUID().uuidString

    /// `ip:port` to advertise over `/signal`, or nil until the listener is bound.
    public init() {}

    public func lanAddress() -> String? {
        guard let port = listener?.port?.rawValue, let ip = Self.localIPv4() else { return nil }
        return "\(ip):\(port)"
    }

    /// A new envelope stamped with this device's identity and the next sequence number.
    func newEnvelope() -> FuseEnvelope {
        sequenceNumber += 1
        var envelope = FuseEnvelope()
        envelope.sourceDeviceID = selfDeviceId ?? ""
        envelope.seq = sequenceNumber
        envelope.sessionID = sessionId
        envelope.sentAtUnixMs = Int64(Date().timeIntervalSince1970 * 1000)
        return envelope
    }

    /// Brings the listener up, returning only once it is bound and has a port.
    ///
    /// The caller announces this device over `/signal` immediately after this returns, and
    /// that hello carries `lanAddress()`. Returning early left the very first hello
    /// advertising no address at all, so the peer had nothing to dial and could not reach
    /// this Mac until the next reconnect — which looked exactly like a network fault.
    public func start(deviceId: String) async {
        stop()
        selfDeviceId = deviceId
        do {
            let listener = try NWListener(using: .tcp)
            self.listener = listener
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                // Resumed exactly once: a continuation resumed twice traps, and this
                // handler fires again on every later state change.
                var resumed = false
                listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready, .failed, .cancelled:
                        guard !resumed else { return }
                        resumed = true
                        continuation.resume()
                    default:
                        break
                    }
                }
                listener.start(queue: .global(qos: .userInitiated))
            }
            heartbeatTask = Task { [weak self] in await self?.heartbeatLoop() }
        } catch {
            // Fail soft: without a listener this device can still dial peers whose id
            // sorts higher, and the next start() retries.
            listener = nil
        }
    }

    public func stop() {
        acceptTask?.cancel()
        heartbeatTask?.cancel()
        acceptTask = nil
        heartbeatTask = nil
        supervisors.values.forEach { $0.cancel() }
        supervisors.removeAll()
        channels.values.forEach { $0.close() }
        channels.removeAll()
        listener?.cancel()
        listener = nil
        peers.removeAll()
        setConnected([])
    }

    /// Fed from `SignalClient`; drives who we dial and which keys we accept.
    public func updatePeers(_ presence: [String: PeerPresence]) {
        peers = presence
        guard let selfId = selfDeviceId else { return }
        for peerId in presence.keys where Self.dialsFirst(selfId: selfId, peerId: peerId) {
            guard supervisors[peerId] == nil else { continue }
            supervisors[peerId] = Task { [weak self] in await self?.maintain(peerId, selfId: selfId) }
        }
    }

    /// Dials every unconnected peer now instead of waiting out its backoff, which grows to
    /// 15 s. What the popover's Connect button runs, so a phone that just joined the Wi-Fi
    /// links while the user is still looking rather than on the next retry.
    public func retryNow() {
        for (peerId, task) in supervisors where channels[peerId] == nil {
            task.cancel()
            supervisors[peerId] = nil
        }
        updatePeers(peers)
    }

    /// Ordered, back-pressured send to every connected peer.
    ///
    /// Unlike `broadcast` this waits for each write to reach the socket, which is what
    /// keeps a file's chunks from queueing the entire file in memory ahead of the network.
    /// Fail soft: a dead channel is dropped, not thrown.
    func send(_ envelope: FuseEnvelope) async {
        for (peerId, channel) in channels {
            do {
                try await channel.send(envelope)
            } catch {
                drop(peerId, channel: channel)
            }
        }
    }

    /// Fail-soft broadcast to every connected peer; a dead channel is dropped, not thrown.
    func broadcast(_ envelope: FuseEnvelope) {
        for (peerId, channel) in channels {
            Task { [weak self] in
                do {
                    try await channel.send(envelope)
                } catch {
                    self?.drop(peerId, channel: channel)
                }
            }
        }
    }

    // MARK: - Connection lifecycle

    private func accept(_ connection: NWConnection) {
        Task { [weak self] in
            guard let self, let selfId = self.selfDeviceId else {
                connection.cancel()
                return
            }
            do {
                connection.start(queue: .global(qos: .userInitiated))
                try await connection.waitUntilReady()
                let channel = try await self.handshake(connection, selfId: selfId)
                await self.pump(channel)
            } catch {
                FuseLog.lan.warning("inbound handshake failed: \(error.localizedDescription, privacy: .public)")
                connection.cancel() // fail soft: a bad caller is just dropped
            }
        }
    }

    private func maintain(_ peerId: String, selfId: String) async {
        var backoff: UInt64 = 500
        while !Task.isCancelled {
            if let peer = peers[peerId], peer.online,
               let address = peer.lanAddress, peer.publicKey != nil
            {
                let connected = await dial(peerId, address: address, selfId: selfId)
                backoff = connected ? 500 : min(backoff * 2, 15_000)
            }
            try? await Task.sleep(nanoseconds: backoff * 1_000_000)
        }
    }

    private func dial(_ peerId: String, address: String, selfId: String) async -> Bool {
        guard let (host, port) = Self.parseAddress(address) else { return false }
        let connection = NWConnection(
            host: NWEndpoint.Host(host), port: port, using: .tcp,
        )
        do {
            connection.start(queue: .global(qos: .userInitiated))
            try await connection.waitUntilReady()
            let channel = try await handshake(connection, selfId: selfId)
            await pump(channel)
            return true
        } catch {
            FuseLog.lan.warning("dial to \(peerId, privacy: .public) at \(address, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            connection.cancel()
            return false
        }
    }

    private func handshake(_ connection: NWConnection, selfId: String) async throws -> LanChannel {
        let privateKey = try DeviceKey.privateKey()
        let known = peers
        return try await LanChannel.handshake(
            connection: connection,
            selfDeviceId: selfId,
            privateKey: privateKey,
            trustedKeyFor: { id in
                guard let encoded = known[id]?.publicKey else { return nil }
                return try? DeviceKey.decodePublic(base64: encoded)
            },
        )
    }

    /// Receive loop for one channel; returns when the connection ends.
    private func pump(_ channel: LanChannel) async {
        register(channel)
        defer {
            drop(channel.peerDeviceId, channel: channel)
        }
        while !Task.isCancelled {
            do {
                let envelope = try await channel.receive()
                switch envelope.body {
                case .some(.heartbeat), .none:
                    break // liveness only; nothing above the transport cares
                case .some(.fileMeta), .some(.fileChunk), .some(.ack), .some(.fileCancel):
                    onFileEnvelope?(envelope)
                case .some(.clipText), .some(.clipImage):
                    onEnvelope?(envelope)
                }
            } catch {
                return
            }
        }
    }

    private func heartbeatLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !channels.isEmpty else { continue }
            var envelope = newEnvelope()
            envelope.heartbeat = FuseHeartbeat()
            broadcast(envelope)
        }
    }

    private func register(_ channel: LanChannel) {
        FuseLog.lan.info("channel up with \(channel.peerDeviceId, privacy: .public)")
        // A reconnect replaces the previous channel rather than racing it.
        channels[channel.peerDeviceId]?.close()
        channels[channel.peerDeviceId] = channel
        setConnected(connectedPeers.union([channel.peerDeviceId]))
    }

    private func drop(_ peerId: String, channel: LanChannel) {
        guard channels[peerId] === channel else { return }
        channels.removeValue(forKey: peerId)
        channel.close()
        setConnected(connectedPeers.subtracting([peerId]))
    }

    private func setConnected(_ value: Set<String>) {
        connectedPeers = value
        onConnectedPeersChanged?(value)
    }

    // MARK: - Helpers

    /// The lower device id dials; the higher one listens.
    /// Internal so the tie-break, which decides whether a pair connects at all, is testable.
    static func dialsFirst(selfId: String, peerId: String) -> Bool { selfId < peerId }

    /// Parses a peer's advertised `host:port`.
    ///
    /// This is peer-supplied input arriving over the network, so everything malformed
    /// must come back nil and skip the dial rather than produce an endpoint that cannot
    /// work. Splits on the LAST colon so a bracketed IPv6 literal survives.
    static func parseAddress(_ value: String) -> (String, NWEndpoint.Port)? {
        guard
            let separator = value.lastIndex(of: ":"),
            let port = NWEndpoint.Port(String(value[value.index(after: separator)...])),
            port.rawValue > 0 // port 0 is "any port", never something to dial
        else { return nil }
        let host = String(value[value.startIndex ..< separator])
        guard !host.isEmpty else { return nil }
        return (host, port)
    }

    /// This Mac's LAN IPv4 address, as peers must dial it.
    private static func localIPv4() -> String? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return nil }
        defer { freeifaddrs(addresses) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(pointer.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            guard pointer.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_INET) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                pointer.pointee.ifa_addr,
                socklen_t(pointer.pointee.ifa_addr.pointee.sa_len),
                &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST,
            ) == 0 else { continue }

            let address = String(cString: host)
            // Skip link-local; a peer cannot route to 169.254.x.x without the interface.
            if !address.hasPrefix("169.254") { return address }
        }
        return nil
    }
}
