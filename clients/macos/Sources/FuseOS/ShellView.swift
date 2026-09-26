import SwiftUI
import FuseOSCore

/// The five areas of the signed-in app. Same five as Android's bar, in Mac clothing.
enum FuseSection: String, CaseIterable, Identifiable {
    case home = "Home"
    case history = "History"
    case devices = "Devices"
    case screen = "Screen"
    case account = "Account"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: return "square.grid.2x2"
        case .history: return "clock.arrow.circlepath"
        case .devices: return "laptopcomputer.and.iphone"
        case .screen: return "rectangle.on.rectangle"
        case .account: return "person.crop.circle"
        }
    }
}

/// The signed-in Mac app: one full-bleed pane under a floating glass bar.
///
/// No sidebar. Five destinations fit in one capsule, and giving the pane the whole width
/// suits content that is mostly one column of cards. The five areas are the same as
/// Android's bar; only the furniture differs.
struct ShellView: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject var viewModel: DashboardViewModel
    @State private var showPairing = false

    @State private var section: FuseSection = .home

    var body: some View {
        // The ZStack is what lets the old pane leave and the new one arrive as a transition.
        ZStack {
            pane
                .id(section)
                .transition(.opacity.combined(with: .offset(y: 10)))
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // Scrolling panes slide under the bar; the glass is what makes that readable.
            .safeAreaInset(edge: .top, spacing: 0) {
                GlassNav(section: $section, viewModel: viewModel)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
            }
            .background(ShellBackground())
            .ignoresSafeArea(edges: .top)
            .frame(minWidth: 720, minHeight: 520)
            .onAppear {
                viewModel.start()
                // Reaching the shell means the user is set up, which is the honest moment to
                // start at login — not at first launch, when they have not decided to keep it.
                if !DemoMode.isOn { LaunchAtLogin.enableOnFirstRun() }
            }
            .onReceive(NotificationCenter.default.publisher(for: DemoMode.showSection)) { note in
                if let raw = note.object as? String, let target = FuseSection(rawValue: raw) { section = target }
            }
            .sheet(isPresented: $showPairing) {
                PairingView(viewModel: viewModel).environmentObject(session)
            }
            // A share started on the phone should land in front of the user, not in a tab
            // they would have to think to open.
            .onChange(of: viewModel.screenState) { state in
                if case .streaming = state { go(.screen) }
            }
    }

    @ViewBuilder private var pane: some View {
        switch section {
        case .home:
            HomePane(viewModel: viewModel, onSeeAll: { go(.history) }, onMirror: {
                go(.screen)
                viewModel.screen.start()
            })
        case .history:
            HistoryPane(viewModel: viewModel)
        case .devices:
            DevicesPane(viewModel: viewModel, onLinkManually: { showPairing = true })
        case .screen:
            ScreenPane(viewModel: viewModel)
        case .account:
            AccountPane(viewModel: viewModel, onLinkManually: { showPairing = true })
        }
    }

    private func go(_ target: FuseSection) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { section = target }
    }
}

/// The floating bar: the five areas in a glass capsule, the open one lit in ember, and the
/// link state at the end — the thing people glance at, so it is on every pane.
private struct GlassNav: View {
    @Binding var section: FuseSection
    @ObservedObject var viewModel: DashboardViewModel
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(FuseSection.allCases.enumerated()), id: \.element) { index, item in
                tab(item, shortcut: Character(String(index + 1)))
            }
            Divider().frame(height: 18).padding(.horizontal, 6)
            linkState.padding(.trailing, 8)
        }
        .padding(5)
        .modifier(GlassCapsule())
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }

    private func tab(_ item: FuseSection, shortcut: Character) -> some View {
        let selected = item == section
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { section = item }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: item.symbol)
                    .font(.system(size: 13, weight: .medium))
                if selected {
                    Text(item.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .fixedSize()
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
                }
            }
            .foregroundStyle(selected ? FuseColor.accent : FuseColor.muted)
            .padding(.horizontal, selected ? 12 : 10)
            .frame(height: 30)
            .background {
                if selected {
                    Capsule()
                        .fill(FuseColor.accent.opacity(0.16))
                        .overlay(Capsule().stroke(FuseColor.accent.opacity(0.35), lineWidth: 1))
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(shortcut), modifiers: .command)
        .help("\(item.rawValue)  ⌘\(shortcut)")
    }

    private var linkState: some View {
        let linked = !viewModel.connected.isEmpty
        return HStack(spacing: 6) {
            Circle()
                .fill(linked ? FuseColor.accent : FuseColor.muted.opacity(0.6))
                .frame(width: 7, height: 7)
                .shadow(color: linked ? FuseColor.accent : .clear, radius: 4)
            Text(linked ? (viewModel.peerName ?? "Linked") : "Not linked")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(linked ? FuseColor.ink : FuseColor.muted)
                .lineLimit(1)
        }
    }
}

/// Liquid Glass capsule on macOS 26; a material capsule before it.
private struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(FuseColor.outline.opacity(0.5), lineWidth: 1))
        }
    }
}

/// The window's ground: the app's slate, with the ember glowing up from behind the bar.
/// Glass over a flat colour reads as flat; this gives it something to bend.
private struct ShellBackground: View {
    var body: some View {
        ZStack {
            FuseColor.bg
            RadialGradient(
                colors: [FuseColor.accent.opacity(0.22), .clear],
                center: UnitPoint(x: 0.5, y: -0.15),
                startRadius: 0,
                endRadius: 420,
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Panes

/// Home: the link, then two columns — what was copied, and what is moving.
private struct HomePane: View {
    @ObservedObject var viewModel: DashboardViewModel
    let onSeeAll: () -> Void
    let onMirror: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                LinkHero(viewModel: viewModel, onMirror: onMirror)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        VStack(spacing: 18) {
                            nowPlaying
                            clipboard
                        }
                        .frame(minWidth: 420)
                        files.frame(width: 340)
                    }
                    VStack(spacing: 18) {
                        nowPlaying
                        clipboard
                        files
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .frame(maxWidth: 1040)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private var nowPlaying: some View {
        if let track = viewModel.nowPlaying {
            NowPlayingPanel(track: track, remote: viewModel.media)
        }
    }

    private var clipboard: some View {
        Panel(title: "Clipboard", accessory: {
            Button("See all", action: onSeeAll)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(FuseColor.accent)
        }) {
            if viewModel.history.isEmpty {
                EmptyNote(symbol: "doc.on.clipboard", text: "Copy something on either device and it shows up here.")
            } else {
                VStack(spacing: 2) {
                    // Six proves sync is alive without turning Home into History.
                    ForEach(viewModel.history.prefix(6)) { entry in
                        ClipRow(entry: entry, peerName: viewModel.peerName) {
                            viewModel.copyToClipboard(entry)
                        }
                    }
                }
            }
        }
    }

    private var files: some View {
        VStack(spacing: 18) {
            PhoneActionsPanel(viewModel: viewModel, onMirror: onMirror)
            filesPanel
        }
    }

    private var filesPanel: some View {
        Panel(title: "Files") {
            VStack(spacing: 10) {
                FileDropZone(viewModel: viewModel)
                ForEach(viewModel.transfers.prefix(4)) { transfer in
                    TransferRow(transfer: transfer, peerName: viewModel.peerName, viewModel: viewModel)
                }
            }
        }
    }
}

/// What the phone is playing: artwork, track, a bar that advances by itself, and the
/// three controls anyone reaches for.
private struct NowPlayingPanel: View {
    let track: NowPlaying
    let remote: MediaRemote

    var body: some View {
        HStack(spacing: 16) {
            Group {
                if let data = track.artwork, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(FuseColor.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(FuseColor.accent.opacity(0.12))
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FuseColor.ink)
                    .lineLimit(1)
                Text([track.artist, track.appName].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundStyle(FuseColor.muted)
                    .lineLimit(1)
                if track.durationMs > 0 {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let position = track.position(at: context.date)
                        HStack(spacing: 8) {
                            Text(Self.clock(position)).monospacedDigit()
                            ProgressBar(fraction: Double(position) / Double(track.durationMs))
                            Text(Self.clock(track.durationMs)).monospacedDigit()
                        }
                        .font(.system(size: 10.5))
                        .foregroundStyle(FuseColor.muted)
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                control("backward.fill", action: remote.previous)
                control(track.playing ? "pause.fill" : "play.fill", large: true, action: remote.playPause)
                control("forward.fill", action: remote.next)
            }
        }
        .padding(16)
        .panelSurface(radius: 18)
    }

    private func control(_ symbol: String, large: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: large ? 15 : 12, weight: .semibold))
                .foregroundStyle(large ? Color.white : FuseColor.ink)
                .frame(width: large ? 40 : 32, height: large ? 40 : 32)
                .background(Circle().fill(large ? FuseColor.accent : FuseColor.surfaceAlt))
        }
        .buttonStyle(.plain)
    }

    private static func clock(_ ms: Int64) -> String {
        let seconds = Int(ms / 1000)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// One-click things to do with the phone: find it, borrow its camera, hand it a link, see
/// its screen. Each is a message on the LAN channel; none waits on the server.
private struct PhoneActionsPanel: View {
    @ObservedObject var viewModel: DashboardViewModel
    let onMirror: () -> Void
    @State private var ringing = false

    var body: some View {
        let linked = !viewModel.connected.isEmpty
        Panel(title: "Your phone") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                action(ringing ? "Stop ringing" : "Ring", symbol: ringing ? "speaker.slash.fill" : "bell.and.waves.left.and.right.fill") {
                    if ringing {
                        viewModel.phone.stopRinging()
                        ringing = false
                    } else {
                        viewModel.phone.ring()
                        ringing = true
                        // The phone stops by itself after 30 s; so does this button.
                        Task {
                            try? await Task.sleep(nanoseconds: 30_000_000_000)
                            ringing = false
                        }
                    }
                }
                action("Take photo", symbol: "camera.fill") { viewModel.phone.takePhoto() }
                    .help("Opens the camera on your phone; the photo lands on this Mac's clipboard")
                action("Open copied link", symbol: "safari.fill") {
                    if let url = viewModel.clipboardLink { viewModel.openOnPhone(url) }
                }
                .disabled(viewModel.clipboardLink == nil)
                .help("Opens the link on this Mac's clipboard in your phone's browser")
                action("Mirror", symbol: "rectangle.on.rectangle", run: onMirror)
            }
            .disabled(!linked)
        }
    }

    private func action(_ title: String, symbol: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(FuseColor.accent)
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(FuseColor.ink)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(FuseColor.surfaceAlt))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The top of Home: this Mac and the phone, joined by the filament a spark runs along while
/// they are linked. The one showy thing in the app — it answers the question people open
/// it to ask. Everything below it stays quiet.
private struct LinkHero: View {
    @ObservedObject var viewModel: DashboardViewModel
    let onMirror: () -> Void

    var body: some View {
        let peer = viewModel.peers.first { viewModel.isConnected($0) } ?? viewModel.peers.first
        let linked = peer.map(viewModel.isConnected) ?? false
        return HStack(spacing: 28) {
            HStack(spacing: 0) {
                endpoint(symbol: "laptopcomputer", name: viewModel.selfDevice?.name ?? "This Mac", lit: true)
                Filament(linked: linked)
                    .frame(height: 24)
                    .padding(.horizontal, 4)
                endpoint(symbol: "iphone", name: peer?.name ?? "Your phone", lit: linked)
            }
            .frame(maxWidth: 420)

            VStack(alignment: .leading, spacing: 6) {
                StatusPill(linked: linked, text: linked ? "Linked · direct" : status)
                Text(peer?.name ?? "No phone yet")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(FuseColor.ink)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(FuseColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if let peer, let battery = viewModel.onlineState(for: peer).battery {
                        BatteryBadge(percent: battery)
                    }
                    if linked, let latency = viewModel.syncLatency {
                        // The PRD's own yardstick: p95 under 300 ms, shown where people look.
                        Label("\(latency.lastMs) ms · p95 \(latency.p95Ms) ms", systemImage: "bolt.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(latency.p95Ms < 300 ? FuseColor.muted : FuseColor.error)
                            .monospacedDigit()
                            .help("Round trip of the last clip, and the 95th percentile of the last \(latency.samples)")
                    }
                    Spacer(minLength: 0)
                    Button(action: onMirror) {
                        Label("Mirror screen", systemImage: "rectangle.on.rectangle")
                    }
                    .buttonStyle(CapsuleButtonStyle(prominent: false))
                    .disabled(!linked)
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 26)
        .background(heroBackground)
        .animation(.easeInOut(duration: 0.4), value: linked)
    }

    /// The panel surface with the ember rising from its bottom edge — the hero's own glow.
    private var heroBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return shape.fill(FuseColor.surface)
            .overlay(
                shape.fill(RadialGradient(
                    colors: [FuseColor.accent.opacity(0.10), .clear],
                    center: UnitPoint(x: 0.25, y: 1.1), startRadius: 0, endRadius: 360,
                )),
            )
            .overlay(shape.stroke(FuseColor.outline.opacity(0.55), lineWidth: 1))
    }

    private var status: String {
        switch viewModel.connectState.stage {
        case .connected: return "Linked · direct"
        case .connecting: return "Connecting"
        case .differentNetwork: return "Different networks"
        case .peerOffline: return "Phone offline"
        case .alone: return "Waiting for a phone"
        }
    }

    private var detail: String {
        switch viewModel.connectState.stage {
        case .connected: return "Clipboard, files and notifications move straight over your Wi-Fi."
        case .connecting: return "Finding your phone on this Wi-Fi…"
        case .differentNetwork: return "Put both devices on the same Wi-Fi network."
        case .peerOffline: return "Open FuseOS on your phone to link it."
        case .alone: return "Sign in on your phone with this account."
        }
    }

    private func endpoint(symbol: String, name: String, lit: Bool) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(FuseColor.accent.opacity(lit ? 0.15 : 0.05))
                    .frame(width: 60, height: 60)
                Circle()
                    .stroke(FuseColor.accent.opacity(lit ? 0.35 : 0.1), lineWidth: 1)
                    .frame(width: 60, height: 60)
                Image(systemName: symbol)
                    .font(.system(size: 23, weight: .light))
                    .foregroundStyle(lit ? FuseColor.accent : FuseColor.muted)
            }
            Text(name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(FuseColor.muted)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 104)
        }
    }
}

/// The line between the two devices. Linked, a spark runs along it; not linked, it is a
/// dim dashed gap. Motion only while there is something live to show.
private struct Filament: View {
    let linked: Bool

    var body: some View {
        TimelineView(.animation(paused: !linked)) { context in
            Canvas { ctx, size in
                let y = size.height / 2
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                if linked {
                    ctx.stroke(line, with: .color(FuseColor.accent.opacity(0.3)), lineWidth: 1.5)
                    // One trip every 1.8 s, eased so it gathers at each end like a hand-off.
                    let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8
                    let x = size.width * (0.5 - cos(t * .pi) / 2)
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 9, y: y - 9, width: 18, height: 18)),
                             with: .color(FuseColor.accent.opacity(0.22)))
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 3.5, y: y - 3.5, width: 7, height: 7)),
                             with: .color(FuseColor.accent))
                } else {
                    ctx.stroke(line, with: .color(FuseColor.muted.opacity(0.4)),
                               style: StrokeStyle(lineWidth: 1.5, dash: [4, 6]))
                }
            }
        }
        .frame(minWidth: 60)
        .accessibilityHidden(true)
    }
}

/// Everything ever copied, grouped by day, in one panel.
private struct HistoryPane: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var window: HistoryWindow = .day

    var body: some View {
        let shown = window.filter(viewModel.history)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .lastTextBaseline) {
                    PaneTitle("Clipboard history", subtitle: "Click an item to put it back on this Mac's clipboard.")
                    Spacer()
                    Picker("", selection: $window) {
                        ForEach(HistoryWindow.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 300)
                }

                if shown.isEmpty {
                    Panel {
                        // "Nothing in 24 hours" and "nothing ever" need different answers: one
                        // is a filter to widen, the other is a feature to try.
                        EmptyNote(
                            symbol: "clock.arrow.circlepath",
                            text: viewModel.history.isEmpty
                                ? "Nothing yet. Copy something on either device and it lands here."
                                : "Nothing copied in the last \(window.label.lowercased()). Try a wider range.",
                        )
                    }
                } else {
                    ForEach(Self.days(shown), id: \.title) { day in
                        Panel(title: day.title) {
                            VStack(spacing: 2) {
                                ForEach(day.entries) { entry in
                                    ClipRow(entry: entry, peerName: viewModel.peerName) {
                                        viewModel.copyToClipboard(entry)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
    }

    /// Entries (already newest first) split into Today / Yesterday / dated groups.
    private static func days(_ entries: [ClipEntry]) -> [(title: String, entries: [ClipEntry])] {
        let calendar = Calendar.current
        var groups: [(title: String, entries: [ClipEntry])] = []
        for entry in entries {
            let title: String
            if calendar.isDateInToday(entry.at) {
                title = "Today"
            } else if calendar.isDateInYesterday(entry.at) {
                title = "Yesterday"
            } else {
                title = entry.at.formatted(.dateTime.weekday(.wide).day().month(.wide))
            }
            if groups.last?.title == title {
                groups[groups.count - 1].entries.append(entry)
            } else {
                groups.append((title, [entry]))
            }
        }
        return groups
    }
}

private struct DevicesPane: View {
    @ObservedObject var viewModel: DashboardViewModel
    let onLinkManually: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PaneTitle("Devices", subtitle: "Everything signed in to this account links itself.")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                    SelfDeviceRow(name: viewModel.selfDevice?.name)
                    // Every record, stale ones included, so an old one can be removed here.
                    ForEach(viewModel.devicesByStanding) { peer in
                        DeviceRow(
                            device: peer,
                            presence: viewModel.onlineState(for: peer),
                            isConnected: viewModel.isConnected(peer),
                            onRemove: { Task { await viewModel.removeDevice(peer) } },
                        )
                    }
                }
                HStack(spacing: 10) {
                    Button("Link with a code", action: onLinkManually)
                        .buttonStyle(CapsuleButtonStyle(prominent: false))
                    Text("Only needed if a device on this account didn't show up.")
                        .font(.system(size: 12))
                        .foregroundStyle(FuseColor.muted)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
    }
}

/// Settings, grouped the way macOS groups them: this Mac, how FuseOS behaves, the account.
private struct AccountPane: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject var viewModel: DashboardViewModel
    let onLinkManually: () -> Void

    @State private var draftName = ""
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @AppStorage(DockIcon.key) private var showInDock = true
    @AppStorage(DashboardViewModel.askBeforeSendKey) private var askBeforeSend = false
    @AppStorage(MacPointer.enabledKey) private var phoneControlsMac = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(FuseColor.accent.opacity(0.16)).frame(width: 52, height: 52)
                        Text((session.email ?? "?").prefix(1).uppercased())
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(FuseColor.accent)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.email ?? "Signed in")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(FuseColor.ink)
                        Text("\(viewModel.peers.count + 1) devices · \(viewModel.connected.count) linked")
                            .font(.system(size: 12))
                            .foregroundStyle(FuseColor.muted)
                    }
                }

                Panel(title: "This Mac") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            FuseTextField(title: "Device name", text: $draftName)
                            Button("Save") {
                                let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !trimmed.isEmpty else { return }
                                session.setDeviceName(trimmed)
                                // Push it now rather than at the next launch, so the phone's
                                // list updates while the user is still looking at the change.
                                Task { await viewModel.refresh(reregister: true) }
                            }
                            .buttonStyle(CapsuleButtonStyle(prominent: true))
                            .disabled(draftName.trimmingCharacters(in: .whitespaces) == (session.deviceName ?? ""))
                        }
                        Text("Your phone shows this name.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(FuseColor.muted)
                    }
                }
                .onAppear { draftName = session.deviceName ?? SessionStore.detectedDeviceName() }

                Panel(title: "Behaviour") {
                    VStack(spacing: 0) {
                        SettingSwitch(
                            title: "Start at login",
                            detail: "Sync is ready before you reach for it.",
                            isOn: Binding(
                                get: { launchAtLogin },
                                set: { launchAtLogin = LaunchAtLogin.setEnabled($0) ? $0 : LaunchAtLogin.isEnabled },
                            ),
                        )
                        Divider().opacity(0.5)
                        SettingSwitch(
                            title: "Show in Dock",
                            detail: "Off, FuseOS lives in the menu bar only.",
                            isOn: $showInDock,
                        )
                        .onChange(of: showInDock) { shown in
                            DockIcon.apply(shown)
                            // Leaving the Dock deactivates the app; keep this window in front
                            // of the user who is still looking at it.
                            DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
                        }
                        Divider().opacity(0.5)
                        SettingSwitch(
                            title: "Ask before sending copies",
                            detail: "Each copy waits in the island for you to click Send.",
                            isOn: $askBeforeSend,
                        )
                        Divider().opacity(0.5)
                        SettingSwitch(
                            title: "Let your phone control this Mac",
                            detail: MacPointer.accessibilityGranted(prompt: false) || !phoneControlsMac
                                ? "Use your phone as this Mac's trackpad and keyboard."
                                : "Allow FuseOS in System Settings → Privacy & Security → Accessibility.",
                            isOn: $phoneControlsMac,
                        )
                        .onChange(of: phoneControlsMac) { on in
                            // macOS decides; this only asks it to show its own prompt.
                            if on { MacPointer.accessibilityGranted(prompt: true) }
                        }
                    }
                }

                Panel(title: "Account") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Link with a code").font(.system(size: 13, weight: .medium))
                                Text("Devices on this account link themselves; this is the fallback.")
                                    .font(.system(size: 11.5)).foregroundStyle(FuseColor.muted)
                            }
                            Spacer()
                            Button("Show code", action: onLinkManually)
                                .buttonStyle(CapsuleButtonStyle(prominent: false))
                        }
                        Divider().opacity(0.5)
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sign out").font(.system(size: 13, weight: .medium))
                                Text("Clears this Mac's session and its clipboard history.")
                                    .font(.system(size: 11.5)).foregroundStyle(FuseColor.muted)
                            }
                            Spacer()
                            Button("Sign out") {
                                viewModel.signOut()
                                session.clear()
                            }
                            .buttonStyle(CapsuleButtonStyle(prominent: false, destructive: true))
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct SettingSwitch: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(FuseColor.ink)
                Text(detail).font(.system(size: 11.5)).foregroundStyle(FuseColor.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .tint(FuseColor.accent)
        .padding(.vertical, 9)
    }
}

/// The phone's screen, live. View only: controlling the phone would need an
/// AccessibilityService, which is off the table (see CLAUDE.md).
private struct ScreenPane: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        let linked = !viewModel.connected.isEmpty
        VStack(spacing: 18) {
            switch viewModel.screenState {
            case .streaming(let width, let height):
                PhoneScreen(layer: viewModel.screen.layer, onInput: viewModel.screen.send)
                    .aspectRatio(CGFloat(width) / CGFloat(max(height, 1)), contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 6))
                    .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
                    .frame(maxHeight: .infinity)
                if viewModel.canControlPhone {
                    HStack(spacing: 8) {
                        Button { viewModel.screen.send(.back) } label: { Image(systemName: "chevron.backward") }
                            .help("Back  (Esc)")
                        Button { viewModel.screen.send(.home) } label: { Image(systemName: "circle") }
                            .help("Home")
                        Button { viewModel.screen.send(.recents) } label: { Image(systemName: "square.on.square") }
                            .help("Recent apps")
                        Divider().frame(height: 16)
                        Button("Stop mirroring") { viewModel.screen.stop() }
                    }
                    .buttonStyle(CapsuleButtonStyle(prominent: false))
                    Text("Click to tap · drag to swipe · hold to long-press · type to enter text")
                        .font(.system(size: 11.5))
                        .foregroundStyle(FuseColor.muted)
                } else {
                    Button("Stop mirroring") { viewModel.screen.stop() }
                        .buttonStyle(CapsuleButtonStyle(prominent: false))
                        .keyboardShortcut(.escape, modifiers: [])
                    Text("View only. Turn on Remote control in FuseOS on your phone to use it from here.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(FuseColor.muted)
                }
            case .requesting:
                placeholder(
                    title: "Check your phone",
                    detail: "Tap Start now on \(viewModel.peerName ?? "your phone") to share its screen.",
                    busy: true,
                )
                Button("Cancel") { viewModel.screen.stop() }
                    .buttonStyle(CapsuleButtonStyle(prominent: false))
            case .idle, .ended:
                placeholder(
                    title: viewModel.screenState == .ended ? "Mirroring ended" : "Your phone, on this Mac",
                    detail: linked
                        ? "See your phone's screen live, straight over your Wi-Fi."
                        : "Link your phone first — mirroring runs over the same direct connection.",
                    busy: false,
                )
                Button(viewModel.screenState == .ended ? "Mirror again" : "Mirror \(viewModel.peerName ?? "phone")") {
                    viewModel.screen.start()
                }
                .buttonStyle(CapsuleButtonStyle(prominent: true))
                .disabled(!linked)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func placeholder(title: String, detail: String, busy: Bool) -> some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(FuseColor.surface)
                    .frame(width: 132, height: 240)
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(FuseColor.outline, lineWidth: 1)
                    .frame(width: 132, height: 240)
                Capsule().fill(FuseColor.outline).frame(width: 38, height: 5).offset(y: -106)
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(FuseColor.accent)
                }
            }
            Text(title)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(FuseColor.ink)
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(FuseColor.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .padding(.bottom, 6)
    }
}

/// Hosts the receiver's display layer, and turns what the user does on it into input for
/// the phone: a click is a tap, a hold a long-press, a drag a swipe, the scroll wheel a
/// swipe, and typing goes to the phone's focused field (Esc is Back).
private struct PhoneScreen: NSViewRepresentable {
    let layer: CALayer
    let onInput: (ScreenReceiver.Input) -> Void

    func makeNSView(context: Context) -> MirrorView {
        let view = MirrorView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        layer.frame = view.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(layer)
        view.onInput = onInput
        return view
    }

    func updateNSView(_ view: MirrorView, context: Context) {
        view.onInput = onInput
    }
}

final class MirrorView: NSView {
    var onInput: ((ScreenReceiver.Input) -> Void)?
    private var downAt: (point: CGPoint, time: TimeInterval)?
    private var scrollAccumulated: CGFloat = 0
    private var scrollFlush: DispatchWorkItem?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true } // top-left origin, as the phone counts
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    /// 0–1 of the view, which the aspect-fit frame keeps equal to the phone's screen.
    private func normalized(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x / max(bounds.width, 1), 0), 1),
                y: min(max(point.y / max(bounds.height, 1), 0), 1))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        downAt = (convert(event.locationInWindow, from: nil), event.timestamp)
    }

    override func mouseUp(with event: NSEvent) {
        guard let down = downAt else { return }
        downAt = nil
        let up = convert(event.locationInWindow, from: nil)
        let held = event.timestamp - down.time
        let a = normalized(down.point), b = normalized(up)
        if hypot(up.x - down.point.x, up.y - down.point.y) < 6 {
            onInput?(held > 0.5 ? .longPress(x: a.x, y: a.y) : .tap(x: a.x, y: a.y))
        } else {
            onInput?(.swipe(fromX: a.x, fromY: a.y, toX: b.x, toY: b.y, durationMs: Int(held * 1000)))
        }
    }

    /// Wheel and trackpad scrolls arrive as dozens of small deltas; they are gathered and
    /// sent as one swipe once they pause, so the phone scrolls once rather than stuttering.
    override func scrollWheel(with event: NSEvent) {
        scrollAccumulated += event.scrollingDeltaY
        scrollFlush?.cancel()
        let flush = DispatchWorkItem { [weak self] in
            guard let self, abs(self.scrollAccumulated) > 2 else { return }
            let travel = min(max(self.scrollAccumulated / max(self.bounds.height, 1), -0.6), 0.6)
            self.onInput?(.swipe(fromX: 0.5, fromY: 0.5, toX: 0.5, toY: 0.5 + travel, durationMs: 180))
            self.scrollAccumulated = 0
        }
        scrollFlush = flush
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: flush)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 51: onInput?(.delete)
        case 36, 76: onInput?(.enter)
        case 53: onInput?(.back)
        default:
            let typed = (event.characters ?? "").filter { !$0.isASCII || !($0.asciiValue.map { $0 < 32 || $0 == 127 } ?? false) }
            if !typed.isEmpty { onInput?(.text(typed)) }
        }
    }
}

// MARK: - Files

/// Drop files here, or choose them. Either way they go to the connected phone.
private struct FileDropZone: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var targeted = false

    var body: some View {
        let linked = !viewModel.connected.isEmpty
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(spacing: 10) {
            Image(systemName: targeted ? "arrow.down.doc.fill" : "arrow.up.doc")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(targeted || linked ? FuseColor.accent : FuseColor.muted)
            Text(linked ? "Drop files for \(viewModel.peerName ?? "your phone")" : "Link a device to send files")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(FuseColor.ink)
                .multilineTextAlignment(.center)
            Button("Choose files", action: choose)
                .buttonStyle(CapsuleButtonStyle(prominent: true))
                .disabled(!linked)
            if let notice = viewModel.fileNotice {
                Text(notice)
                    .font(.system(size: 11))
                    .foregroundStyle(FuseColor.error)
            }
        }
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .background(shape.fill(targeted ? FuseColor.accent.opacity(0.08) : FuseColor.surfaceAlt.opacity(0.6)))
        .overlay(
            shape.stroke(targeted ? FuseColor.accent : FuseColor.outline.opacity(0.8),
                         style: StrokeStyle(lineWidth: 1, dash: [5, 4])),
        )
        .animation(.easeOut(duration: 0.15), value: targeted)
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            viewModel.sendFiles(files)
            return true
        } isTargeted: { targeted = $0 }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        viewModel.sendFiles(panel.urls)
    }
}

/// One file on its way in or out: name, where it is going, a bar, and a way to stop it.
private struct TransferRow: View {
    let transfer: TransferProgress
    let peerName: String?
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        HStack(spacing: 12) {
            IconTile(
                symbol: transfer.outgoing ? "arrow.up" : "arrow.down",
                tint: transfer.state == .failed ? FuseColor.error : FuseColor.accent,
            )
            VStack(alignment: .leading, spacing: 5) {
                Text(transfer.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(FuseColor.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if transfer.finished {
                    Text(status)
                        .font(.system(size: 11.5))
                        .foregroundStyle(transfer.state == .failed ? FuseColor.error : FuseColor.muted)
                } else {
                    ProgressBar(fraction: Double(transfer.bytes) / Double(max(transfer.total, 1)))
                    Text(status)
                        .font(.system(size: 11.5))
                        .foregroundStyle(FuseColor.muted)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
            if !transfer.finished {
                Button {
                    viewModel.cancelTransfer(transfer.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(FuseColor.surfaceAlt))
                }
                .buttonStyle(.plain)
                .foregroundStyle(FuseColor.muted)
                .help("Cancel")
            } else if !transfer.outgoing && transfer.state == .done {
                Button("Show") {
                    if !viewModel.revealTransfer(transfer.id) {
                        viewModel.fileNotice = "\(transfer.name) has moved or been deleted."
                    }
                }
                .buttonStyle(CapsuleButtonStyle(prominent: false))
            }
        }
        .padding(.vertical, 4)
    }

    private var status: String {
        let peer = peerName ?? "your phone"
        let percent = transfer.total > 0 ? transfer.bytes * 100 / transfer.total : 0
        switch transfer.state {
        case .active: return transfer.outgoing ? "To \(peer) · \(percent)%" : "From \(peer) · \(percent)%"
        case .sent: return "Waiting for \(peer) to confirm"
        case .done: return transfer.outgoing ? "Sent to \(peer)" : "Saved to Downloads"
        case .cancelled: return "Cancelled"
        case .failed: return "Didn't go through"
        }
    }
}

// MARK: - Shared bits

/// The app's one card: a solid panel with a hairline edge, and an optional title row.
/// Glass is kept for the floating bar, where there is content underneath to show through.
private struct Panel<Accessory: View, Content: View>: View {
    var title: String?
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    init(
        title: String? = nil,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content,
    ) {
        self.title = title
        self.accessory = accessory
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FuseColor.ink)
                    Spacer()
                    accessory()
                }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelSurface(radius: 18)
    }
}

private struct PaneTitle: View {
    let title: String
    let subtitle: String

    init(_ title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(FuseColor.ink)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(FuseColor.muted)
        }
    }
}

private struct EmptyNote: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, tint: FuseColor.muted)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(FuseColor.muted)
        }
        .padding(.vertical, 6)
    }
}

private struct StatusPill: View {
    let linked: Bool
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(linked ? FuseColor.accent : FuseColor.muted)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(linked ? FuseColor.accent : FuseColor.muted)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill((linked ? FuseColor.accent : FuseColor.muted).opacity(0.12)))
    }
}

private struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(FuseColor.outline.opacity(0.6))
                Capsule()
                    .fill(FuseColor.accent)
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
                    .animation(.easeOut(duration: 0.25), value: fraction)
            }
        }
        .frame(height: 4)
    }
}

/// One clipboard entry: what it is, where it came from, when. Click to copy it back.
struct ClipRow: View {
    let entry: ClipEntry
    /// Named rather than "your phone": the user chose that name, so this is where it earns
    /// its keep. Nil only before a second device joins the account.
    var peerName: String?
    let onCopy: () -> Void
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        Button {
            onCopy()
            copied = true
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                copied = false
            }
        } label: {
            HStack(spacing: 12) {
                if let data = entry.imageData, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                } else {
                    IconTile(symbol: symbol, tint: entry.fromSelf ? FuseColor.muted : FuseColor.accent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(preview)
                        .font(.system(size: 13))
                        .foregroundStyle(FuseColor.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(entry.fromSelf ? "Copied here" : "From \(peerName ?? "your phone")")
                        .font(.system(size: 11))
                        .foregroundStyle(FuseColor.muted)
                }
                Spacer(minLength: 8)
                if copied {
                    Label("Copied", systemImage: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FuseColor.accent)
                } else if hovering {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(FuseColor.muted)
                } else {
                    Text(entry.at, style: .time)
                        .font(.system(size: 11))
                        .foregroundStyle(FuseColor.muted)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(hovering ? FuseColor.surfaceAlt : Color.clear),
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var symbol: String {
        guard let text = entry.text else { return "photo" }
        if text.hasPrefix("http://") || text.hasPrefix("https://") { return "link" }
        return "text.alignleft"
    }

    private var preview: String {
        if entry.isImage { return "Image" }
        // A two-line preview reads as one thought; raw newlines made it a ragged fragment.
        return (entry.text ?? "").split(whereSeparator: \.isNewline).joined(separator: "  ")
    }
}
