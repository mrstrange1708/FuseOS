import Foundation

/// What we know about a peer right now.
///
/// `publicKey` and `lanAddress` are what make a direct connection possible: the address
/// says where to dial, the key says who must answer. Both arrive from the control plane,
/// which is the only thing that can vouch for them.
public struct PeerPresence {
    public let online: Bool
    public let battery: Int?
    public let publicKey: String?
    public let lanAddress: String?
    /// The peer's name as the server last announced it; nil until one has been.
    public let name: String?

    public init(online: Bool, battery: Int?, publicKey: String?, lanAddress: String?, name: String? = nil) {
        self.online = online
        self.battery = battery
        self.publicKey = publicKey
        self.lanAddress = lanAddress
        self.name = name
    }
}

/// A decoded `/signal` server frame (only the fields the dashboard needs).
private struct SignalEvent: Decodable {
    let type: String
    let from: String?
    let stream: String?
    let data: String?
    let close: Bool?
    let deviceId: String?
    let battery: Int?
    let online: Bool?
    let publicKey: String?
    let lanAddress: String?
    let name: String?
    let peers: [PeerCard]?
}

private struct PeerCard: Decodable {
    let deviceId: String
    let battery: Int?
    let online: Bool?
    let publicKey: String?
    let lanAddress: String?
    let name: String?
}

/// Maintains the `/signal` WebSocket: authenticates with a `hello`, sends battery
/// heartbeats, and surfaces peer presence via callbacks. Fail-soft — a dropped
/// socket reconnects with a short delay and never crashes the app.
@MainActor
public final class SignalClient {
    /// Everything currently known about this account's other devices.
    public private(set) var presence: [String: PeerPresence] = [:]

    public var onPresenceChanged: (([String: PeerPresence]) -> Void)?

    /// A piece of a relayed channel (docs/protocol.md §19): sealed bytes, or `close`.
    public var onRelay: ((_ from: String, _ stream: String, _ data: Data?, _ close: Bool) -> Void)?

    /// The live socket for relay sends, readable off the main thread: a channel's writes come
    /// from its own actor, in order, and URLSessionWebSocketTask keeps the order of `send`
    /// calls — hopping to the main actor first would not.
    private let relayLock = NSLock()
    private nonisolated(unsafe) var relayTask: URLSessionWebSocketTask?

    /// Sends a piece of a relayed channel; false when there is no live socket.
    public nonisolated func sendRelay(to: String, stream: String, data: Data?, close: Bool = false) -> Bool {
        relayLock.lock()
        let task = relayTask
        relayLock.unlock()
        guard let task else { return false }
        var payload: [String: Any] = ["type": "relay", "to": to, "stream": stream]
        if let data { payload["data"] = data.base64EncodedString() }
        if close { payload["close"] = true }
        guard let json = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: json, encoding: .utf8) else { return false }
        task.send(.string(text)) { _ in } // fail soft: a lost piece ends the channel's next read
        return true
    }

    private func setRelayTask(_ task: URLSessionWebSocketTask?) {
        relayLock.lock()
        relayTask = task
        relayLock.unlock()
    }

    /// Supplies this device's `ip:port` for peers to dial. The LAN listener binds an
    /// ephemeral port, so this is nil until it is up and changes across restarts — hence
    /// a closure rather than a stored value.
    public var lanAddressProvider: (() -> String?)?

    private var task: URLSessionWebSocketTask?
    private var token: String?
    private var deviceId: String?
    private var active = false
    private var heartbeat: Task<Void, Never>?

    public init() {}

    public func start(token: String, deviceId: String) {
        self.token = token
        self.deviceId = deviceId
        active = true
        connect()
    }

    public func stop() {
        active = false
        heartbeat?.cancel()
        heartbeat = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        setRelayTask(nil)
    }

    private func connect() {
        guard active, let token, let deviceId else { return }
        let socket = URLSession.shared.webSocketTask(with: Config.signalURL)
        task = socket
        setRelayTask(socket)
        socket.resume()

        var hello: [String: Any] = ["type": "hello", "token": token, "deviceId": deviceId]
        if let battery = Battery.currentPercent() { hello["battery"] = battery }
        if let lanAddress = lanAddressProvider?() { hello["lanAddress"] = lanAddress }
        send(hello)

        receiveLoop()
        startHeartbeat()
    }

    private func startHeartbeat() {
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard let self, self.active else { return }
                var frame: [String: Any] = ["type": "heartbeat"]
                if let battery = Battery.currentPercent() { frame["battery"] = battery }
                if let lanAddress = self.lanAddressProvider?() { frame["lanAddress"] = lanAddress }
                self.send(frame)
            }
        }
    }

    private func send(_ payload: [String: Any]) {
        guard
            let task,
            let data = try? JSONSerialization.data(withJSONObject: payload),
            let text = String(data: data, encoding: .utf8)
        else { return }
        task.send(.string(text)) { _ in }  // fail soft
    }

    private func receiveLoop() {
        Task { @MainActor in
            guard let socket = self.task else { return }
            do {
                let message = try await socket.receive()
                if case let .string(text) = message { self.handle(text) }
                if self.active { self.receiveLoop() }
            } catch {
                if self.active { self.scheduleReconnect() }
            }
        }
    }

    private func scheduleReconnect() {
        guard active else { return }
        task = nil
        setRelayTask(nil)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard self.active else { return }
            self.connect()
        }
    }

    /// Internal rather than private so tests can feed real server frames straight in,
    /// without standing up a WebSocket.
    func handle(_ text: String) {
        guard
            let data = text.data(using: .utf8),
            let event = try? JSONDecoder().decode(SignalEvent.self, from: data)
        else { return }

        switch event.type {
        case "relay":
            guard let from = event.from, let stream = event.stream else { return }
            onRelay?(from, stream, event.data.flatMap { Data(base64Encoded: $0) }, event.close == true)
        case "hello-ok":
            for peer in event.peers ?? [] {
                setPresence(
                    peer.deviceId, online: peer.online ?? true, battery: peer.battery,
                    publicKey: peer.publicKey, lanAddress: peer.lanAddress, name: peer.name,
                )
            }
        case "peer-online", "peer-update":
            if let id = event.deviceId {
                setPresence(
                    id, online: true, battery: event.battery,
                    publicKey: event.publicKey, lanAddress: event.lanAddress, name: event.name,
                )
            }
        case "peer-offline":
            // Keep the key and address on the way down: the peer is unreachable now, but
            // the details are still valid when it comes back and save a round trip.
            if let id = event.deviceId {
                setPresence(id, online: false, battery: nil, publicKey: nil, lanAddress: nil)
            }
        default:
            break
        }
    }

    private func setPresence(
        _ deviceId: String,
        online: Bool,
        battery: Int?,
        publicKey: String?,
        lanAddress: String?,
        name: String? = nil,
    ) {
        let existing = presence[deviceId]
        presence[deviceId] = PeerPresence(
            online: online,
            battery: battery ?? existing?.battery,
            publicKey: publicKey ?? existing?.publicKey,
            lanAddress: lanAddress ?? existing?.lanAddress,
            name: name ?? existing?.name,
        )
        onPresenceChanged?(presence)
    }
}
