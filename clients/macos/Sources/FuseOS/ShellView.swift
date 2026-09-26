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
                LaunchAtLogin.enableOnFirstRun()
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
            HomePane(viewModel: viewModel, onSeeAll: { go(.history) })
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

private struct HomePane: View {
    @ObservedObject var viewModel: DashboardViewModel
    let onSeeAll: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                LinkHero(viewModel: viewModel, statusLine: statusLine)

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Files")
                    FileDropZone(viewModel: viewModel)
                    ForEach(viewModel.transfers) { transfer in
                        TransferRow(transfer: transfer, peerName: viewModel.peerName, viewModel: viewModel)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SectionLabel("Recent")
                        Spacer()
                        Button("See all", action: onSeeAll)
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(FuseColor.accent)
                    }
                    if viewModel.history.isEmpty {
                        Text("Nothing yet. Copy something on either device.")
                            .font(.system(size: 13))
                            .foregroundStyle(FuseColor.muted)
                    } else {
                        // Five is enough to prove sync is alive without turning home into
                        // the history pane; the rest is one click away.
                        ForEach(viewModel.history.prefix(5)) { entry in
                            ClipRow(entry: entry, peerName: viewModel.peerName) {
                                viewModel.copyToClipboard(entry)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .padding(.bottom, 28)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
    }

    private var statusLine: String {
        switch viewModel.connectState.stage {
        case .connected: return "Clipboard and files move directly over your Wi-Fi."
        case .connecting: return "Connecting over your Wi-Fi…"
        case .differentNetwork: return "Your devices are on different networks."
        case .peerOffline: return "Open FuseOS on your phone to link it."
        case .alone: return "Sign in on your phone with this account."
        }
    }
}

/// The top of Home: this Mac and the phone, joined by the filament. The one place in the
/// app that is allowed to be showy — it answers the only question people open it to ask.
private struct LinkHero: View {
    @ObservedObject var viewModel: DashboardViewModel
    let statusLine: String

    var body: some View {
        let peer = viewModel.peers.first { viewModel.isConnected($0) } ?? viewModel.peers.first
        let linked = peer.map(viewModel.isConnected) ?? false
        return VStack(spacing: 18) {
            HStack(spacing: 0) {
                endpoint(symbol: "laptopcomputer", name: viewModel.selfDevice?.name ?? "This Mac", lit: true)
                Filament(linked: linked)
                    .frame(height: 24)
                    .padding(.horizontal, 6)
                endpoint(symbol: "iphone", name: peer?.name ?? "Your phone", lit: linked)
            }
            VStack(spacing: 5) {
                Text(linked ? "Linked to \(peer?.name ?? "your phone")" : (peer == nil ? "No phone yet" : "Not linked"))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(FuseColor.ink)
                Text(statusLine)
                    .font(.system(size: 12))
                    .foregroundStyle(FuseColor.muted)
                if let peer, let battery = viewModel.onlineState(for: peer).battery {
                    BatteryBadge(percent: battery).padding(.top, 2)
                }
            }
            .multilineTextAlignment(.center)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity)
        .glassCard(radius: 22)
        .animation(.easeInOut(duration: 0.4), value: linked)
    }

    private func endpoint(symbol: String, name: String, lit: Bool) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(FuseColor.accent.opacity(lit ? 0.16 : 0.06))
                    .frame(width: 62, height: 62)
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(lit ? FuseColor.accent : FuseColor.muted)
            }
            Text(name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(FuseColor.muted)
                .lineLimit(1)
                .frame(maxWidth: 110)
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
                    ctx.stroke(line, with: .color(FuseColor.accent.opacity(0.35)), lineWidth: 2)
                    // One trip every 1.8 s, eased so it gathers at each end like a hand-off.
                    let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8
                    let eased = 0.5 - cos(t * .pi) / 2
                    let x = size.width * eased
                    let glow = Path(ellipseIn: CGRect(x: x - 9, y: y - 9, width: 18, height: 18))
                    ctx.fill(glow, with: .color(FuseColor.accent.opacity(0.25)))
                    let spark = Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8))
                    ctx.fill(spark, with: .color(FuseColor.accent))
                } else {
                    ctx.stroke(line, with: .color(FuseColor.muted.opacity(0.4)),
                               style: StrokeStyle(lineWidth: 1.5, dash: [4, 6]))
                }
            }
        }
        .frame(minWidth: 80)
        .accessibilityHidden(true)
    }
}

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(FuseColor.ink)
    }
}

private struct HistoryPane: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var window: HistoryWindow = .day

    var body: some View {
        let shown = window.filter(viewModel.history)
        return VStack(alignment: .leading, spacing: 14) {
            PaneTitle("Clipboard history", subtitle: "Click an item to put it back on this Mac's clipboard.")

            Picker("", selection: $window) {
                ForEach(HistoryWindow.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 360)

            if shown.isEmpty {
                // "Nothing in 24 hours" and "nothing ever" need different answers: one is
                // a filter to widen, the other is a feature to try.
                Text(viewModel.history.isEmpty
                     ? "Nothing yet. Copy something on either device and it lands here."
                     : "Nothing copied in the last \(window.label.lowercased()). Try a wider range.")
                    .font(.system(size: 13))
                    .foregroundStyle(FuseColor.muted)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(shown) { entry in
                            ClipRow(entry: entry, peerName: viewModel.peerName) {
                                viewModel.copyToClipboard(entry)
                            }
                        }
                    }
                }
            }
        }
        .padding(28)
        .frame(maxWidth: 680, alignment: .leading)
        .frame(maxWidth: .infinity)
    }
}

private struct DevicesPane: View {
    @ObservedObject var viewModel: DashboardViewModel
    let onLinkManually: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaneTitle("Devices", subtitle: "Everything signed in to this account.")

            SelfDeviceRow(name: viewModel.selfDevice?.name)

            ForEach(viewModel.peers) { peer in
                DeviceRow(
                    device: peer,
                    presence: viewModel.onlineState(for: peer),
                    isConnected: viewModel.isConnected(peer),
                )
            }

            Text("Any device signed in to this account links itself.")
                .font(.system(size: 11))
                .foregroundStyle(FuseColor.muted)
            Button("Link manually", action: onLinkManually)
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(FuseColor.accent)
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: 640, alignment: .leading)
        .frame(maxWidth: .infinity)
    }
}

private struct AccountPane: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject var viewModel: DashboardViewModel
    let onLinkManually: () -> Void

    @State private var draftName = ""
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @AppStorage(DockIcon.key) private var showInDock = true
    @AppStorage(DashboardViewModel.askBeforeSendKey) private var askBeforeSend = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaneTitle("Account", subtitle: session.email ?? "Signed in")

            VStack(alignment: .leading, spacing: 6) {
                Text("This Mac's name")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FuseColor.ink)
                HStack {
                    FuseTextField(title: "Device name", text: $draftName)
                    Button("Save") {
                        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        session.setDeviceName(trimmed)
                        // Push it now rather than at the next launch, so the phone's list
                        // updates while the user is still looking at the change.
                        Task { await viewModel.refresh(reregister: true) }
                    }
                }
                Text("Your phone shows this name.")
                    .font(.system(size: 11))
                    .foregroundStyle(FuseColor.muted)
            }
            .onAppear { draftName = session.deviceName ?? SessionStore.detectedDeviceName() }

            Divider().padding(.vertical, 2)

            HStack(spacing: 12) {
                Text("\(viewModel.peers.count + 1) devices")
                Text("·")
                Text("\(viewModel.connected.count) linked")
            }
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(FuseColor.muted)

            Divider().padding(.vertical, 4)

            Toggle("Start FuseOS at login", isOn: Binding(
                get: { launchAtLogin },
                set: { launchAtLogin = LaunchAtLogin.setEnabled($0) ? $0 : LaunchAtLogin.isEnabled },
            ))
            .toggleStyle(.checkbox)
            .font(.system(size: 12))

            Toggle("Show in Dock", isOn: $showInDock)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .onChange(of: showInDock) { shown in
                    DockIcon.apply(shown)
                    // Leaving the Dock deactivates the app; keep this window in front of
                    // the user who is still looking at it.
                    DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
                }

            Toggle("Ask before sending copies", isOn: $askBeforeSend)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .help("Each copy waits in the island for you to click Send. Off, copies go instantly.")

            Button("Link manually", action: onLinkManually)
            Button("Sign out") {
                viewModel.signOut()
                session.clear()
            }
            .foregroundStyle(FuseColor.error)

            Text("Signing out clears this Mac's session and its stored clipboard history.")
                .font(.system(size: 11))
                .foregroundStyle(FuseColor.muted)
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: 560, alignment: .leading)
        .frame(maxWidth: .infinity)
    }
}

/// The phone's screen, live. View only: controlling the phone would need an
/// AccessibilityService, which is off the table (see CLAUDE.md).
private struct ScreenPane: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        let linked = !viewModel.connected.isEmpty
        VStack(spacing: 16) {
            switch viewModel.screenState {
            case .streaming(let width, let height):
                PhoneScreen(layer: viewModel.screen.layer)
                    .aspectRatio(CGFloat(width) / CGFloat(max(height, 1)), contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 6))
                    .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
                    .frame(maxHeight: .infinity)
                Button("Stop mirroring") { viewModel.screen.stop() }
                    .keyboardShortcut(.escape, modifiers: [])
            case .requesting:
                placeholder(
                    title: "Check your phone",
                    detail: "Tap Start now on \(viewModel.peerName ?? "your phone") to share its screen.",
                    busy: true,
                )
                Button("Cancel") { viewModel.screen.stop() }
            case .idle, .ended:
                placeholder(
                    title: viewModel.screenState == .ended ? "Mirroring ended" : "See your phone here",
                    detail: linked
                        ? "Your phone's screen, live on this Mac over your Wi-Fi."
                        : "Link your phone first — mirroring runs over the same direct connection.",
                    busy: false,
                )
                Button(viewModel.screenState == .ended ? "Mirror again" : "Mirror \(viewModel.peerName ?? "phone")") {
                    viewModel.screen.start()
                }
                .buttonStyle(.borderedProminent)
                .tint(FuseColor.accent)
                .controlSize(.large)
                .disabled(!linked)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func placeholder(title: String, detail: String, busy: Bool) -> some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(FuseColor.outline, style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                    .frame(width: 120, height: 220)
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "iphone.gen3")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(FuseColor.muted)
                }
            }
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(FuseColor.ink)
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(FuseColor.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxHeight: .infinity)
    }
}

/// Hosts the receiver's display layer. The layer decodes and draws on its own.
private struct PhoneScreen: NSViewRepresentable {
    let layer: CALayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        layer.frame = view.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(layer)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Files

/// Drop files here, or click to choose them. Either way they go to the connected phone.
private struct FileDropZone: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var targeted = false

    var body: some View {
        let linked = !viewModel.connected.isEmpty
        VStack(spacing: 6) {
            Image(systemName: "arrow.up.doc")
                .font(.system(size: 20))
                .foregroundStyle(targeted ? FuseColor.accent : FuseColor.muted)
            Text(linked ? "Drop files to send them to \(viewModel.peerName ?? "your phone")" : "Link a device to send files")
                .font(.system(size: 12))
                .foregroundStyle(FuseColor.ink)
            Button("Choose…", action: choose)
                .disabled(!linked)
            if let notice = viewModel.fileNotice {
                Text(notice)
                    .font(.system(size: 11))
                    .foregroundStyle(FuseColor.error)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(targeted ? FuseColor.accent.opacity(0.08) : FuseColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(targeted ? FuseColor.accent : FuseColor.outline.opacity(0.6),
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])),
        )
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
        HStack(spacing: 10) {
            Image(systemName: transfer.outgoing ? "arrow.up.circle" : "arrow.down.circle")
                .foregroundStyle(FuseColor.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(transfer.name)
                    .font(.system(size: 13))
                    .foregroundStyle(FuseColor.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(status)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(transfer.state == .failed ? FuseColor.error : FuseColor.muted)
                if !transfer.finished {
                    ProgressView(value: Double(transfer.bytes), total: Double(max(transfer.total, 1)))
                        .progressViewStyle(.linear)
                }
            }
            Spacer(minLength: 0)
            if !transfer.finished {
                Button {
                    viewModel.cancelTransfer(transfer.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(FuseColor.muted)
                .help("Cancel")
            } else if !transfer.outgoing && transfer.state == .done {
                Button("Show in Finder") {
                    if !viewModel.revealTransfer(transfer.id) {
                        viewModel.fileNotice = "\(transfer.name) has moved or been deleted."
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(FuseColor.accent)
            }
        }
        .padding(12)
        .glassCard(radius: 12)
    }

    private var status: String {
        let peer = peerName ?? "your phone"
        let percent = transfer.total > 0 ? transfer.bytes * 100 / transfer.total : 0
        switch transfer.state {
        case .active: return transfer.outgoing ? "Sending to \(peer) · \(percent)%" : "Receiving from \(peer) · \(percent)%"
        case .sent: return "Waiting for \(peer) to confirm"
        case .done: return transfer.outgoing ? "Sent to \(peer)" : "Saved to Downloads"
        case .cancelled: return "Cancelled"
        case .failed: return "Didn't go through"
        }
    }
}

// MARK: - Shared bits

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
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(FuseColor.ink)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(FuseColor.muted)
        }
    }
}

/// One clipboard entry. Shared by the home pane, the history pane and the menu bar.
struct ClipRow: View {
    let entry: ClipEntry
    /// Named rather than "your phone": the user chose that name, so this is where it earns
    /// its keep. Nil only before a second device joins the account.
    var peerName: String?
    let onCopy: () -> Void

    var body: some View {
        Button(action: onCopy) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(entry.fromSelf ? "Copied here" : "From \(peerName ?? "your phone")")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(FuseColor.accent)
                    Spacer()
                    Text(entry.at, style: .time)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(FuseColor.muted)
                }
                if let data = entry.imageData, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Text(entry.text ?? "")
                        .font(.system(size: 13))
                        .foregroundStyle(FuseColor.ink)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(radius: 14)
        }
        .buttonStyle(.plain)
    }
}
