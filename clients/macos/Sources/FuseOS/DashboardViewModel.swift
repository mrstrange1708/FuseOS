import AppKit
import Combine
import Foundation
import FuseOSCore

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var selfDevice: DeviceItem?
    /// Every other device on the account, as the server lists them.
    @Published var allPeers: [DeviceItem] = []
    @Published var presence: [String: PeerPresence] = [:]
    /// Peers reachable over a direct LAN channel, not merely online.
    @Published var connected: Set<String> = []
    @Published var errorMessage: String?
    @Published var isLoading = false
    /// Everything copied here or received from a peer, newest first.
    @Published var history: [ClipEntry] = []
    /// Files in flight and recently finished, newest first.
    @Published var transfers: [TransferProgress] = []
    /// Why the last attempt to send a file did not start, until the next attempt.
    @Published var fileNotice: String?

    let signal = SignalClient()
    let transport = LanTransport()
    private lazy var clipboard = ClipboardSync(transport: transport)
    /// Verified files land in Downloads (`FileTransfer.defaultDirectory`).
    private lazy var files = FileTransfer(transport: transport)
    /// Where each received file was saved, so its row can reveal it in Finder.
    private var receivedURLs: [String: URL] = [:]
    /// How fast clips have been crossing, once any has been acknowledged.
    @Published var syncLatency: SyncLatency?
    /// Screen mirroring's state, for the Screen pane.
    @Published var screenState: ScreenReceiver.State = .idle
    /// The phone will act on clicks and typing on its mirror (see `ScreenReceiver.canControl`).
    @Published var canControlPhone = false
    /// The phone's screen. Created up front: it registers the transport's screen hook.
    lazy var screen = ScreenReceiver(transport: transport)
    private lazy var notifications = NotificationMirror(transport: transport)
    /// Ring the phone, ask it for a photo, hand links across.
    lazy var phone = PhoneCommands(transport: transport)
    /// What the phone is playing, and the controls for it.
    lazy var media = MediaRemote(transport: transport)
    @Published var nowPlaying: NowPlaying?
    private let notifier = PhoneNotifier()
    /// The notch HUD. Owned here because this is where clip events already arrive.
    private let island = ClipIsland()
    private var started = false
    private var sessionWatch: AnyCancellable?

    init() {
        // Sign-out and an expired session both end in the token going. Either way sync
        // stops, and the next sign-in starts it afresh (ShellView calls start()).
        sessionWatch = SessionStore.shared.$token
            .removeDuplicates()
            .sink { [weak self] token in
                guard token == nil else { return }
                Task { @MainActor in self?.sessionEnded() }
            }
    }

    private func sessionEnded() {
        guard started else { return }
        stop()
        started = false
        startTask = nil
        allPeers = []
        presence = [:]
        connected = []
    }
    /// In flight or finished registration. Cleared on failure so the next action retries.
    private var startTask: Task<String, Error>?

    static let askBeforeSendKey = "askBeforeSend"

    func start() {
        guard !started else { return }
        started = true
        if DemoMode.isOn {
            DemoMode.fill(self)
            return
        }
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
                id != self.selfDevice?.id && !self.allPeers.contains { $0.id == id }
            }) {
                Task { await self.refresh() }
            }
        }
        // Both ends send their history on every new channel, and each merges what it lacks.
        transport.onPeersJoined = { [weak self] _ in self?.clipboard.sendHistory() }
        notifications.onPosted = { [weak self] n in
            self?.island.present(n)
            self?.notifier.post(n)
        }
        notifications.onRemoved = { [weak self] key in self?.notifier.remove(key: key) }
        notifier.onUserDismissed = { [weak self] key in self?.notifications.dismiss(key: key) }
        screen.onStateChanged = { [weak self] state in self?.screenState = state }
        screen.onCanControlChanged = { [weak self] can in self?.canControlPhone = can }
        media.onChange = { [weak self] playing in self?.nowPlaying = playing }
        phone.onOpenLink = { [weak self] url in
            NSWorkspace.shared.open(url)
            self?.island.present(symbol: "safari", title: "Opened from \(self?.peerName ?? "your phone")", detail: url.host ?? url.absoluteString)
        }
        transport.onConnectedPeersChanged = { [weak self] peers in
            self?.connected = peers
            if peers.isEmpty { self?.media.peerGone() }
            self?.files.peersChanged(peers)
        }
        clipboard.onHistoryChanged = { [weak self] entries in
            self?.history = entries
        }
        // Creating `files` is what wires the transport's file hook, so this first touch
        // must happen before any peer can connect.
        files.onFileReceived = { [weak self] file in
            // Size only: a file name is user content, and content never reaches a log.
            FuseLog.lan.info("file received, \(file.size, privacy: .public) bytes")
            self?.receivedURLs[file.transferId] = file.url
        }
        files.onProgress = { [weak self] progress in
            guard let self else { return }
            // ponytail: newest 20 only; a record of every file ever sent belongs in a
            // history store, which files do not have yet.
            self.transfers = Array(([progress] + self.transfers.filter { $0.id != progress.id }).prefix(20))
            // Files get the island too: it swells out of the notch and fills as bytes move.
            self.island.present(progress, peerName: self.peerName)
        }
        // Asking is opt-in (Account → "Ask before sending copies"); read per copy so the
        // toggle applies at once. With nothing linked there is no one to ask about.
        clipboard.onLocalCopy = { [weak self] offer in
            guard let self else { return }
            if UserDefaults.standard.bool(forKey: Self.askBeforeSendKey), !self.connected.isEmpty {
                self.island.offer(offer, peerName: self.peerName)
            } else {
                offer.send()
            }
        }
        clipboard.onLatency = { [weak self] latency in self?.syncLatency = latency }
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
        screen.stop()
        signal.stop()
        files.stop()
        clipboard.stop()
        transport.stop()
    }

    /// Sign-out, as distinct from `stop()`: the stored history goes too, and the session
    /// ends on the server as well as here.
    func signOut() {
        if let token = SessionStore.shared.token {
            Task.detached { await AuthAPI.signOut(token: token) }
        }
        island.dismiss()
        signal.stop()
        files.stop()
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
            allPeers = all.filter { !$0.isSelf }
            errorMessage = nil
        } catch {
            errorMessage = (error as? AuthError)?.message ?? error.localizedDescription
        }
        isLoading = false
    }

    /// Manual linking, the safety net behind automatic linking. Both calls resolve the
    /// device id through `ensureStarted`, so opening the sheet after a failed launch
    /// registers then rather than refusing.
    func initiatePairing() async throws -> String {
        try await ControlPlane.initiatePairing(deviceId: ensureStarted()).code
    }

    func claimPairing(code: String) async throws {
        _ = try await ControlPlane.claimPairing(deviceId: ensureStarted(), code: code)
        await refresh()
    }

    /// The devices worth showing. A reinstall mints a new key and so a new device record,
    /// leaving the old one on the account forever offline under the same name; showing both
    /// reads as "your phone is offline" right next to "linked". Per name and platform, the
    /// connected record wins, then the online one.
    ///
    /// ponytail: hides stale records rather than deleting them; a "Remove device" action on
    /// the server is the real fix when the account screen grows one.
    var peers: [DeviceItem] {
        func rank(_ d: DeviceItem) -> Int {
            connected.contains(d.id) ? 0 : onlineState(for: d).online ? 1 : 2
        }
        var best: [String: DeviceItem] = [:]
        for d in allPeers {
            let key = "\(d.platform)|\(d.name)"
            if let current = best[key], rank(current) <= rank(d) { continue }
            best[key] = d
        }
        return allPeers.filter { best["\($0.platform)|\($0.name)"]?.id == $0.id }
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

    /// Removes a stale (offline) device from the account, then reloads the list.
    func removeDevice(_ device: DeviceItem) async {
        do {
            try await ControlPlane.removeDevice(id: device.id)
            await refresh()
        } catch {
            errorMessage = (error as? AuthError)?.message ?? error.localizedDescription
        }
    }

    /// Every other device, the connected first, then online, then the rest — the Devices
    /// pane's order, which shows stale records so they can be removed.
    var devicesByStanding: [DeviceItem] {
        let rank = Dictionary(uniqueKeysWithValues: allPeers.map { d in
            (d.id, isConnected(d) ? 0 : onlineState(for: d).online ? 1 : 2)
        })
        return allPeers.sorted { rank[$0.id, default: 2] < rank[$1.id, default: 2] }
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

    /// The popover's Connect: re-read which devices are on the account (a phone that just
    /// signed in), then dial everything unconnected at once rather than after its backoff.
    func connect() async {
        await refresh()
        transport.retryNow()
    }

    /// Sends files one after another, in the order given. Dropped or picked, same path.
    func sendFiles(_ urls: [URL]) {
        // Finder can hand over folders (Services, drops); a folder has no single size to
        // put on the wire, so it is skipped rather than failing the whole batch.
        let urls = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true }
        guard !urls.isEmpty else {
            fileNotice = "Folders can't be sent yet. Zip it first."
            return
        }
        guard !connected.isEmpty else {
            fileNotice = "No device connected. Open FuseOS on your phone."
            return
        }
        fileNotice = nil
        Task {
            for url in urls {
                do {
                    try await files.send(fileAt: url)
                } catch FileTransfer.Failure.empty {
                    fileNotice = "\(url.lastPathComponent) is empty."
                } catch FileTransfer.Failure.tooLarge {
                    fileNotice = "\(url.lastPathComponent) is over the 1 GB limit."
                } catch {
                    // A folder lands here too: it has no file size to put on the wire.
                    fileNotice = "Couldn't read \(url.lastPathComponent)."
                }
            }
        }
    }

    func cancelTransfer(_ id: String) { files.cancel(id) }

    /// Selects a received file in Finder. False when it is not there any more.
    func revealTransfer(_ id: String) -> Bool {
        guard let url = receivedURLs[id], FileManager.default.fileExists(atPath: url.path) else { return false }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return true
    }

    /// The link on this Mac's clipboard right now, if there is one — what "Open on phone"
    /// sends.
    var clipboardLink: URL? {
        NSPasteboard.general.string(forType: .string).flatMap(PhoneCommands.firstLink(in:))
    }

    /// Handoff, Mac → phone, for a link picked from anywhere (Services, the Phone panel).
    func openOnPhone(_ url: URL) {
        guard !connected.isEmpty, phone.openOnPhone(url) else { return }
        island.present(symbol: "iphone", title: "Opening on \(peerName ?? "your phone")", detail: url.host ?? url.absoluteString)
    }

    /// Clicking a history entry puts it back on this Mac's clipboard.
    func copyToClipboard(_ entry: ClipEntry) { clipboard.copyToClipboard(entry) }
}
