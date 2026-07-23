import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var selfDevice: DeviceItem?
    @Published var peers: [DeviceItem] = []
    @Published var presence: [String: PeerPresence] = [:]
    /// Peers reachable over a direct LAN channel, not merely online.
    @Published var connected: Set<String> = []
    @Published var errorMessage: String?
    @Published var isLoading = false
    /// Bumped whenever a pairing completes, so an open pairing sheet can dismiss.
    @Published var pairedCount = 0

    let signal = SignalClient()
    let transport = LanTransport()
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        signal.lanAddressProvider = { [weak self] in self?.transport.lanAddress() }
        signal.onPresenceChanged = { [weak self] presence in
            guard let self else { return }
            self.presence = presence
            // The transport dials from the same roster the dashboard displays.
            self.transport.updatePeers(presence)
        }
        signal.onPaired = { [weak self] in
            guard let self else { return }
            self.pairedCount += 1
            Task { await self.refresh() }
        }
        transport.onConnectedPeersChanged = { [weak self] peers in
            self?.connected = peers
        }
        Task { await bootstrap() }
    }

    func stop() {
        signal.stop()
        transport.stop()
    }

    private func bootstrap() async {
        do {
            let deviceId = try await ControlPlane.registerThisDevice(battery: Battery.currentPercent())
            // Bring the listener up before saying hello, so the very first hello can
            // already carry a lanAddress for peers to dial.
            transport.start(deviceId: deviceId)
            if let token = SessionStore.shared.token {
                signal.start(token: token, deviceId: deviceId)
            }
            await refresh()
        } catch {
            errorMessage = (error as? AuthError)?.message ?? error.localizedDescription
        }
    }

    func refresh() async {
        guard let selfId = SessionStore.shared.deviceId else { return }
        isLoading = true
        do {
            let all = try await ControlPlane.listDevices(selfId: selfId)
            selfDevice = all.first { $0.isSelf }
            peers = all.filter { !$0.isSelf }
            errorMessage = nil
        } catch {
            errorMessage = (error as? AuthError)?.message ?? error.localizedDescription
        }
        isLoading = false
    }

    /// Live presence merged over the last REST snapshot for display.
    func onlineState(for device: DeviceItem) -> PeerPresence {
        if let live = presence[device.id] { return live }
        return PeerPresence(
            online: device.online, battery: device.battery, publicKey: nil, lanAddress: nil,
        )
    }

    /// True when there is a live encrypted LAN channel to this device.
    func isConnected(_ device: DeviceItem) -> Bool { connected.contains(device.id) }
}
