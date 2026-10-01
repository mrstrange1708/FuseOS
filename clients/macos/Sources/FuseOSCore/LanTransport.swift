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

    /// Mirrored phone notifications and their dismissals.
    var onNotificationEnvelope: ((FuseEnvelope) -> Void)?

    /// Screen mirroring: control messages and video frames.
    var onScreenEnvelope: ((FuseEnvelope) -> Void)?

    /// Nearby lock and unlock: `BeaconKey`, `Unlocked`.
    var onProximityEnvelope: ((FuseEnvelope) -> Void)?

    /// The other device's battery and charging: `DeviceStatus`.
    var onStatusEnvelope: ((FuseEnvelope) -> Void)?

    /// Sidecar: `SidecarControl`, `SidecarInput` (and our own outgoing frames).
    var onSidecarEnvelope: ((FuseEnvelope) -> Void)?

    /// The phone as trackpad and keyboard: `PointerInput`.
    var onPointerEnvelope: ((FuseEnvelope) -> Void)?

    /// Now Playing: `MediaState`, `MediaCommand`.
    var onMediaEnvelope: ((FuseEnvelope) -> Void)?

    /// Phone actions and links: `PhoneCommand`, `OpenLink`, and `Outcome` — how they went.
    var onActionEnvelope: ((FuseEnvelope) -> Void)?

    /// Fires with the peers that just gained a channel — the moment to exchange history.
    public var onPeersJoined: ((Set<String>) -> Void)?
    /// A heartbeat's round trip, in ms, as its echo comes back (see `Heartbeat` in the proto).
    public var onRoundTrip: ((Int) -> Void)?
    /// When a bulk frame last finished crossing, either way (uptime ns). See `RoundTrip`.
    private var lastBulkAt: UInt64 = 0
    /// Heartbeats sent and not yet echoed: seq → when they went, monotonic nanoseconds.
    private var pings: [UInt64: UInt64] = [:]

    /// Peers with a live direct channel right now — what the UI's "connected" chip reads.
    public private(set) var connectedPeers: Set<String> = []
    public var onConnectedPeersChanged: ((Set<String>) -> Void)?

    private var listener: NWListener?
    private var selfDeviceId: String?
    private var peers: [String: PeerPresence] = [:]
    private var channels: [String: LanChannel] = [:]
    private var supervisors: [String: Task<Void, Never>] = [:]
    /// The user's Disconnect: no link until they choose Connect — channels closed, callers
    /// refused, nothing dialled. The listener stays up, so Connect needs no restart.
    public private(set) var paused = false

    public func setPaused(_ on: Bool) {
        paused = on
        if on { for channel in channels.values { channel.close() } }
    }
    /// When each peer's channel last delivered anything (uptime ns) — how a dead link shows.
    private var lastHeard: [String: UInt64] = [:]
    static let silenceLimit: UInt64 = 45_000_000_000 // three unanswered heartbeats
    static let handshakeTimeout: UInt64 = 10_000_000_000
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
        guard let port = listener?.port?.rawValue, let ip = Self.localIPv4()?.address else { return nil }
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
                // Resumed exactly once: a continuation resumed twice traps. The handler
                // removes itself on the first settled state, on a serial queue, so there is
                // no shared flag for two callbacks to race on.
                listener.stateUpdateHandler = { [weak listener] state in
                    switch state {
                    case .ready, .failed, .cancelled:
                        listener?.stateUpdateHandler = nil
                        continuation.resume()
                    default:
                        break
                    }
                }
                listener.start(queue: DispatchQueue(label: "com.fuseos.lan.listener", qos: .userInitiated))
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
    ///
    /// A peer that normally dials us is dialled too: its dialer may be stuck, and a second
    /// channel only replaces the first (`register`); supervisors skip a peer with a channel.
    public func retryNow() {
        guard !paused else { return }
        for (peerId, task) in supervisors where channels[peerId] == nil {
            task.cancel()
            supervisors[peerId] = nil
        }
        updatePeers(peers)
        guard let selfId = selfDeviceId else { return }
        for (peerId, peer) in peers where channels[peerId] == nil && peer.online && peer.publicKey != nil
            && !Self.dialsFirst(selfId: selfId, peerId: peerId)
        {
            guard let address = peer.lanAddress else { continue }
            Task { [weak self] in _ = await self?.dial(peerId, address: address, selfId: selfId) }
        }
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
                noteTraffic(envelope)
            } catch {
                drop(peerId, channel: channel)
            }
        }
    }

    /// Fail-soft broadcast to every connected peer (or only those in `only`); a dead
    /// channel is dropped, not thrown.
    func broadcast(_ envelope: FuseEnvelope, only: Set<String>? = nil) {
        for (peerId, channel) in channels where only?.contains(peerId) ?? true {
            Task { [weak self] in
                do {
                    try await channel.send(envelope)
                    self?.noteTraffic(envelope)
                } catch {
                    self?.drop(peerId, channel: channel)
                }
            }
        }
    }

    // MARK: - Connection lifecycle

    private func accept(_ connection: NWConnection) {
        Task { [weak self] in
            guard let self, let selfId = self.selfDeviceId, !self.paused else {
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
            // A channel already up (an inbound one, or Connect's) needs no second dial.
            if let peer = peers[peerId], peer.online, channels[peerId] == nil, !paused,
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
        // A peer that accepts and then says nothing must not hold a dial loop forever:
        // cancelling the connection fails the handshake's pending read.
        let watchdog = Task {
            try await Task.sleep(nanoseconds: Self.handshakeTimeout)
            connection.cancel()
        }
        defer { watchdog.cancel() }
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
        // The handshake proves nothing on its own: device ids cross the LAN in the clear, so
        // anyone on the Wi-Fi can open a connection claiming to be the phone. Only the real
        // one can seal a frame under the derived keys, so the channel takes the peer's place —
        // and closes the live link — only once its first frame has decrypted, within the
        // handshake's deadline. Pinging first is what makes that frame arrive (an echo), from
        // builds before this one too.
        var probe = newEnvelope()
        pings[probe.seq] = DispatchTime.now().uptimeNanoseconds
        probe.heartbeat = FuseHeartbeat()
        let deadline = Task {
            try await Task.sleep(nanoseconds: Self.handshakeTimeout)
            channel.close()
        }
        var first: FuseEnvelope?
        do {
            try await channel.send(probe)
            first = try await channel.receive()
        } catch {
            FuseLog.lan.warning("a peer claiming \(channel.peerDeviceId, privacy: .public) never proved itself: \(error.localizedDescription, privacy: .public)")
        }
        deadline.cancel()
        guard let proof = first else {
            channel.close()
            return
        }
        register(channel)
        defer {
            drop(channel.peerDeviceId, channel: channel)
        }
        var pending: FuseEnvelope? = proof // the proof is handled like any other envelope
        while !Task.isCancelled {
            do {
                let envelope: FuseEnvelope
                if let proof = pending {
                    envelope = proof
                    pending = nil
                } else {
                    envelope = try await channel.receive()
                }
                if channels[channel.peerDeviceId] === channel {
                    lastHeard[channel.peerDeviceId] = DispatchTime.now().uptimeNanoseconds
                }
                noteTraffic(envelope)
                switch envelope.body {
                case .some(.heartbeat(let heartbeat)):
                    echo(heartbeat, of: envelope, from: channel.peerDeviceId)
                case .none:
                    break
                // An ack with a transfer id is a file's; one without acknowledges a clip.
                case .some(.ack(let ack)) where ack.refTransferID.isEmpty:
                    onEnvelope?(envelope)
                case .some(.fileMeta), .some(.fileChunk), .some(.ack), .some(.fileCancel):
                    onFileEnvelope?(envelope)
                case .some(.clipText), .some(.clipImage), .some(.historySync):
                    onEnvelope?(envelope)
                case .some(.phoneNotification), .some(.notificationDismiss), .some(.notificationReply),
                     .some(.callState), .some(.callAction), .some(.notificationOpen):
                    onNotificationEnvelope?(envelope)
                case .some(.screenControl), .some(.screenFrame), .some(.remoteInput):
                    onScreenEnvelope?(envelope)
                case .some(.phoneCommand), .some(.openLink), .some(.outcome):
                    onActionEnvelope?(envelope)
                case .some(.mediaState), .some(.mediaCommand):
                    onMediaEnvelope?(envelope)
                case .some(.pointerInput):
                    onPointerEnvelope?(envelope)
                case .some(.sidecarControl), .some(.sidecarInput), .some(.sidecarFrame):
                    onSidecarEnvelope?(envelope)
                case .some(.deviceStatus):
                    onStatusEnvelope?(envelope)
                case .some(.beaconKey), .some(.unlocked), .some(.beaconCheck):
                    onProximityEnvelope?(envelope)
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
            // Every ping is echoed at once, so a live link is never quiet this long. A phone
            // that left the Wi-Fi without a FIN leaves the read blocked for good, and writes
            // still "succeed" into the buffer — silence is the only sign. Closing ends its
            // pump, and the supervisor (or the peer) reconnects.
            let now = DispatchTime.now().uptimeNanoseconds
            var live: Set<String> = []
            for (peerId, channel) in channels {
                let heard = lastHeard[peerId] ?? now
                if now - heard > Self.silenceLimit {
                    FuseLog.lan.warning("no word from \(peerId, privacy: .public) in \((now - heard) / 1_000_000_000) s: reconnecting")
                    channel.close()
                } else {
                    live.insert(peerId)
                }
            }
            if !live.isEmpty { ping(only: live) }
        }
    }

    /// A heartbeat that asks to be echoed, so the link's round trip stays measured.
    private func ping(only: Set<String>? = nil) {
        let envelope = newEnvelope()
        pings[envelope.seq] = DispatchTime.now().uptimeNanoseconds
        // Bounded: a peer that never echoes (an older build) must not grow this.
        if pings.count > 16, let oldest = pings.keys.min() { pings.removeValue(forKey: oldest) }
        var heartbeat = envelope
        heartbeat.heartbeat = FuseHeartbeat()
        broadcast(heartbeat, only: only)
    }

    private func noteTraffic(_ envelope: FuseEnvelope) {
        if RoundTrip.isBulk(envelope) { lastBulkAt = DispatchTime.now().uptimeNanoseconds }
    }

    /// The round trip since `sentAt` in ms, or nil if it measured a queue, not the link.
    func roundTrip(since sentAt: UInt64) -> Int? {
        RoundTrip.ms(sentAt: sentAt, now: DispatchTime.now().uptimeNanoseconds, lastBulkAt: lastBulkAt)
    }

    /// A ping is answered at once, to its sender only; an echo is timed and never answered.
    /// A stale one is neither: it waited in a buffer while one of us slept (`RoundTrip`).
    private func echo(_ heartbeat: FuseHeartbeat, of envelope: FuseEnvelope, from peerId: String) {
        guard RoundTrip.isFresh(sentAtUnixMs: envelope.sentAtUnixMs) else {
            if heartbeat.echoSeq != 0 { pings.removeValue(forKey: heartbeat.echoSeq) }
            return
        }
        if heartbeat.echoSeq == 0 {
            var reply = newEnvelope()
            reply.heartbeat = FuseHeartbeat.with { $0.echoSeq = envelope.seq }
            broadcast(reply, only: [peerId])
        } else if let sentAt = pings.removeValue(forKey: heartbeat.echoSeq), let ms = roundTrip(since: sentAt) {
            onRoundTrip?(ms)
        }
    }

    private func register(_ channel: LanChannel) {
        FuseLog.lan.info("channel up with \(channel.peerDeviceId, privacy: .public)")
        // A reconnect replaces the previous channel rather than racing it.
        channels[channel.peerDeviceId]?.close()
        channels[channel.peerDeviceId] = channel
        lastHeard[channel.peerDeviceId] = DispatchTime.now().uptimeNanoseconds
        setConnected(connectedPeers.union([channel.peerDeviceId]))
        // Every channel, reconnects included: a merge drops what the peer already has.
        onPeersJoined?([channel.peerDeviceId])
        // Time the link straight away rather than 15 s from now.
        ping(only: [channel.peerDeviceId])
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

    /// This Mac's netmask in bits, which decides whether a peer is on the same Wi-Fi.
    public func lanPrefixLength() -> Int? { Self.localIPv4()?.prefixLength }

    /// This Mac's LAN IPv4 address, as peers must dial it, and its netmask in bits.
    private static func localIPv4() -> (address: String, prefixLength: Int)? {
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
            guard !address.hasPrefix("169.254") else { continue }
            let prefix = pointer.pointee.ifa_netmask.map { mask in
                mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    UInt32(bigEndian: $0.pointee.sin_addr.s_addr).nonzeroBitCount
                }
            } ?? 24
            return (address, prefix)
        }
        return nil
    }
}
