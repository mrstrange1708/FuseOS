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
    /// Everything copied here or received from a peer, newest first.
    @Published var history: [ClipEntry] = []

    let signal = SignalClient()
    let transport = LanTransport()
    private lazy var clipboard = ClipboardSync(transport: transport)
    /// The notch HUD. Owned here because this is where clip events already arrive.
    private let island = ClipIsland()
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
            // A device that just signed in on this account arrives as presence before it
            // exists in the REST roster — which holds the names the UI draws. This is how
            // a second device shows up with no pairing step, so it has to self-heal.
            if presence.keys.contains(where: { id in
                id != self.selfDevice?.id && !self.peers.contains { $0.id == id }
            }) {
                Task { await self.refresh() }
            }
        }
        transport.onConnectedPeersChanged = { [weak self] peers in
            self?.connected = peers
        }
        clipboard.onHistoryChanged = { [weak self] entries in
            self?.history = entries
        }
        clipboard.onClipEvent = { [weak self] entry in
            guard let self else { return }
            // Named after whichever peer is actually reachable — with one other device
            // that is always the right name, and with several the connected one is the
            // only one the clip can have come from or gone to.
            self.island.present(entry, peerName: self.peerName)
        }
        Task { await bootstrap() }
    }

    func stop() {
        island.dismiss()
        signal.stop()
        clipboard.stop()
        transport.stop()
    }

    /// Sign-out, as distinct from `stop()`: the stored history goes too.
    func signOut() {
        island.dismiss()
        signal.stop()
        clipboard.forget()
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
            await transport.start(deviceId: deviceId)
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

    /// Reloads the device list. `reregister` re-posts this device first, which is how a
    /// rename reaches the server — registration is an upsert keyed on the public key.
    func refresh(reregister: Bool = false) async {
        isLoading = true
        do {
            if reregister {
                _ = try? await ControlPlane.registerThisDevice(battery: Battery.currentPercent())
            }
            let all = try await ControlPlane.listDevices(selfId: try await ensureStarted())
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

    /// The device a clip most likely came from: the connected one, else the only
    /// one there is. Used wherever the UI would otherwise say "your phone".
    var peerName: String? {
        (peers.first { connected.contains($0.id) } ?? peers.first)?.name
    }

    /// True when there is a live encrypted LAN channel to this device.
    func isConnected(_ device: DeviceItem) -> Bool { connected.contains(device.id) }

    /// What the connect screen renders. Computed rather than stored so it re-derives from
    /// whichever published property just changed, with no third copy of the state to sync.
    var connectState: ConnectState {
        ConnectStateEvaluator.evaluate(
            selfLanAddress: transport.lanAddress(),
            peerIds: peers.map(\.id),
            presence: presence,
            connected: connected,
        )
    }

    /// Clicking a history entry puts it back on this Mac's clipboard.
    func copyToClipboard(_ entry: ClipEntry) { clipboard.copyToClipboard(entry) }
}
