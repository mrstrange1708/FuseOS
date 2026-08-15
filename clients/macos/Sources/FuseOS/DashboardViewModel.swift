import Foundation
import FuseOSCore

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
    private lazy var clipboard = ClipboardSync(transport: transport)
    private var started = false
    /// In flight or finished registration. Cleared on failure so the next action retries.
    private var startTask: Task<String, Error>?

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
        clipboard.stop()
        transport.stop()
    }

    private func bootstrap() async {
        do {
            _ = try await ensureStarted()
            await refresh()
        } catch {
            errorMessage = (error as? AuthError)?.message ?? error.localizedDescription
        }
    }

    /// Registers this device and brings the LAN + signal stack up, returning our device id.
    ///
    /// Every action that needs the id goes through here rather than reading the stored one,
    /// because this runs at launch — when the server may be unreachable. Doing it once and
    /// giving up left the app reporting "this device isn't registered" for the rest of its
    /// life, with a relaunch as the only way out. A failed attempt clears `startTask`, so
    /// the next action retries; concurrent callers await the same attempt rather than
    /// registering twice.
    func ensureStarted() async throws -> String {
        if let startTask { return try await startTask.value }
        let task = Task { () async throws -> String in
            let deviceId = try await ControlPlane.registerThisDevice(battery: Battery.currentPercent())
            // Bring the listener up before saying hello, so the very first hello can
            // already carry a lanAddress for peers to dial.
            transport.start(deviceId: deviceId)
            clipboard.start(selfDeviceId: deviceId)
            if let token = SessionStore.shared.token {
                signal.start(token: token, deviceId: deviceId)
            }
            return deviceId
        }
        startTask = task
        do {
            return try await task.value
        } catch {
            startTask = nil
            throw error
        }
    }

    func refresh() async {
        isLoading = true
        do {
            let all = try await ControlPlane.listDevices(selfId: try await ensureStarted())
            selfDevice = all.first { $0.isSelf }
            peers = all.filter { !$0.isSelf }
            errorMessage = nil
        } catch {
            errorMessage = (error as? AuthError)?.message ?? error.localizedDescription
        }
        isLoading = false
    }

    /// Both pairing calls resolve the device id through `ensureStarted`, so opening the
    /// pairing sheet after a failed launch registers then rather than refusing.
    func initiatePairing() async throws -> String {
        try await ControlPlane.initiatePairing(deviceId: ensureStarted()).code
    }

    func claimPairing(code: String) async throws {
        _ = try await ControlPlane.claimPairing(deviceId: ensureStarted(), code: code)
        await refresh()
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
