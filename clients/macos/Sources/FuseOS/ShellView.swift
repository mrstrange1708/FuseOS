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

/// The signed-in Mac app: a source list and a detail pane.
///
/// Deliberately *not* the phone's bottom bar. A tab bar exists because a thumb reaches the
/// bottom of a phone; a Mac window has width to spare and a sidebar is what people already
/// know here. The five areas are the same on both platforms — only the furniture differs.
struct ShellView: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject var viewModel: DashboardViewModel
    @State private var showPairing = false

    @State private var section: FuseSection = .home

    var body: some View {
        NavigationSplitView {
            List(FuseSection.allCases, selection: Binding(
                get: { section },
                set: { section = $0 ?? section },
            )) { item in
                Label(item.rawValue, systemImage: item.symbol)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 168, ideal: 184, max: 220)
            .safeAreaInset(edge: .bottom) { sidebarStatus }
        } detail: {
            Group {
                switch section {
                case .home:
                    HomePane(viewModel: viewModel, onSeeAll: { section = .history })
                case .history:
                    HistoryPane(viewModel: viewModel)
                case .devices:
                    DevicesPane(viewModel: viewModel, onLinkManually: { showPairing = true })
                case .screen:
                    ComingSoonPane(
                        title: "Screen sharing",
                        detail: "See and control your phone from this Mac.",
                        symbol: "rectangle.on.rectangle",
                    )
                case .account:
                    AccountPane(viewModel: viewModel, onLinkManually: { showPairing = true })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(FuseColor.bg)
        }
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
    }

    /// The link state, always visible regardless of which pane is open — it is the thing
    /// people glance at, and hiding it behind a tab would mean navigating to check.
    private var sidebarStatus: some View {
        let connected = !viewModel.connected.isEmpty
        return HStack(spacing: 8) {
            Circle()
                .fill(connected ? FuseColor.accent : FuseColor.muted)
                .frame(width: 8, height: 8)
            Text(connected ? "Linked" : "Not linked")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(FuseColor.muted)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Panes

private struct HomePane: View {
    @ObservedObject var viewModel: DashboardViewModel
    let onSeeAll: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PaneTitle("Home", subtitle: statusLine)

                Text("Devices")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FuseColor.ink)
                deviceList

                HStack {
                    Text("Recent")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FuseColor.ink)
                    Spacer()
                    Button("See all", action: onSeeAll)
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
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
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusLine: String {
        switch viewModel.connectState.stage {
        case .connected: return "Clipboard and files are moving directly over your network."
        case .connecting: return "Connecting…"
        case .differentNetwork: return "Your devices are on different networks."
        case .peerOffline: return "Your other device is offline."
        case .alone: return "No other device on this account yet."
        }
    }

    private var deviceList: some View {
        VStack(spacing: 10) {
            SelfDeviceRow(name: viewModel.selfDevice?.name)
            ForEach(viewModel.peers) { peer in
                DeviceRow(
                    device: peer,
                    presence: viewModel.onlineState(for: peer),
                    isConnected: viewModel.isConnected(peer),
                )
            }
        }
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AccountPane: View {
    @EnvironmentObject var session: SessionStore
    @ObservedObject var viewModel: DashboardViewModel
    let onLinkManually: () -> Void

    @State private var draftName = ""
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

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
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A destination that exists in the app but not yet in the product.
///
/// Screen sharing is out of scope for v1 (see CLAUDE.md) — it would change the transport
/// design, and clipboard and files come first. The slot is here so the shape of the app is
/// final and does not shift under people later.
private struct ComingSoonPane: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 34))
                .foregroundStyle(FuseColor.muted)
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(FuseColor.ink)
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(FuseColor.muted)
            Label("Coming after clipboard and files", systemImage: "lock")
                .font(.system(size: 11))
                .foregroundStyle(FuseColor.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .background(FuseColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(FuseColor.outline.opacity(0.6), lineWidth: 1),
            )
        }
        .buttonStyle(.plain)
    }
}
