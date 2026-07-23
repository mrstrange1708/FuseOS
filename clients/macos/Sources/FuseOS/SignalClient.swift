import Foundation

/// A decoded `/signal` server frame (only the fields the dashboard needs).
private struct SignalEvent: Decodable {
    let type: String
    let deviceId: String?
    let battery: Int?
    let online: Bool?
    let peers: [PeerCard]?
}

private struct PeerCard: Decodable {
    let deviceId: String
    let battery: Int?
    let online: Bool?
}

/// Maintains the `/signal` WebSocket: authenticates with a `hello`, sends battery
/// heartbeats, and surfaces peer presence via callbacks. Fail-soft — a dropped
/// socket reconnects with a short delay and never crashes the app.
@MainActor
final class SignalClient {
    /// (deviceId, online, battery?) — battery is nil when unchanged.
    var onPresence: ((String, Bool, Int?) -> Void)?
    var onPaired: (() -> Void)?

    private var task: URLSessionWebSocketTask?
    private var token: String?
    private var deviceId: String?
    private var active = false
    private var heartbeat: Task<Void, Never>?

    func start(token: String, deviceId: String) {
        self.token = token
        self.deviceId = deviceId
        active = true
        connect()
    }

    func stop() {
        active = false
        heartbeat?.cancel()
        heartbeat = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func connect() {
        guard active, let token, let deviceId else { return }
        let socket = URLSession.shared.webSocketTask(with: Config.signalURL)
        task = socket
        socket.resume()

        var hello: [String: Any] = ["type": "hello", "token": token, "deviceId": deviceId]
        if let battery = Battery.currentPercent() { hello["battery"] = battery }
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
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard self.active else { return }
            self.connect()
        }
    }

    private func handle(_ text: String) {
        guard
            let data = text.data(using: .utf8),
            let event = try? JSONDecoder().decode(SignalEvent.self, from: data)
        else { return }

        switch event.type {
        case "hello-ok":
            for peer in event.peers ?? [] {
                onPresence?(peer.deviceId, peer.online ?? true, peer.battery)
            }
        case "peer-online":
            if let id = event.deviceId { onPresence?(id, true, event.battery) }
        case "peer-update":
            if let id = event.deviceId { onPresence?(id, true, event.battery) }
        case "peer-offline":
            if let id = event.deviceId { onPresence?(id, false, nil) }
        case "paired":
            onPaired?()
        default:
            break
        }
    }
}
