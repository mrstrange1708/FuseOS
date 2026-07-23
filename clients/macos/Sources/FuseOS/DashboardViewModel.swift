import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    struct PeerPresence {
        var online: Bool
        var battery: Int?
    }

    @Published var selfDevice: DeviceItem?
    @Published var peers: [DeviceItem] = []
    @Published var presence: [String: PeerPresence] = [:]
    @Published var errorMessage: String?
    @Published var isLoading = false
    /// Bumped whenever a pairing completes, so an open pairing sheet can dismiss.
    @Published var pairedCount = 0

    let signal = SignalClient()
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        signal.onPresence = { [weak self] deviceId, online, battery in
            guard let self else { return }
            var state = self.presence[deviceId] ?? PeerPresence(online: online, battery: nil)
            state.online = online
            if let battery { state.battery = battery }
            self.presence[deviceId] = state
        }
        signal.onPaired = { [weak self] in
            guard let self else { return }
            self.pairedCount += 1
            Task { await self.refresh() }
        }
        Task { await bootstrap() }
    }

    func stop() {
        signal.stop()
    }

    private func bootstrap() async {
        do {
            let deviceId = try await ControlPlane.registerThisDevice(battery: Battery.currentPercent())
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
        return PeerPresence(online: device.online, battery: device.battery)
    }
}
