import AppKit
import SwiftUI
import FuseOSCore

/// The FuseOS mark for the menu bar: two devices joined by a filament. A template image, so
/// macOS tints it for light and dark menu bars. Linked fills the right-hand device; not
/// linked leaves both hollow, so the state reads at a glance without opening anything.
enum FuseMenuIcon {
    static func image(linked: Bool) -> NSImage {
        let size = NSSize(width: 26, height: 14)
        let image = NSImage(size: size, flipped: false) { _ in
            let cy: CGFloat = 7, r: CGFloat = 3.6, stroke: CGFloat = 1.6
            let left = NSPoint(x: r + stroke, y: cy)
            let right = NSPoint(x: size.width - r - stroke, y: cy)
            NSColor.black.withAlphaComponent(0.45).setStroke()
            let line = NSBezierPath()
            line.move(to: left)
            line.line(to: right)
            line.lineWidth = stroke
            line.stroke()
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: size.width / 2 - 1.8, y: cy - 1.8, width: 3.6, height: 3.6)).fill()
            NSColor.black.setStroke()
            let ring = NSBezierPath(ovalIn: NSRect(x: left.x - r, y: cy - r, width: r * 2, height: r * 2))
            ring.lineWidth = stroke
            ring.stroke()
            let dot = NSBezierPath(ovalIn: NSRect(x: right.x - r, y: cy - r, width: r * 2, height: r * 2))
            if linked {
                dot.fill()
            } else {
                dot.lineWidth = stroke
                dot.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// The menu bar popover: the app's real home on a Mac.
///
/// Continuity is something you reach for mid-task — yesterday's copied link while writing
/// an email — so everything here is one click from the menu bar: which device is linked,
/// the last clips (click one to copy it back), files in flight, and a way to send one.
/// Drop a file anywhere on it to send that file.
struct MenuBarContent: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.openWindow) private var openWindow
    @State private var copiedId: Int?
    @State private var dropTargeted = false
    @State private var search: SearchPhase = .idle

    private enum SearchPhase: Equatable { case idle, searching, notFound }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if viewModel.connected.isEmpty {
                connectCard
            } else {
                deviceCard
                actionsRow
            }
            if let track = viewModel.nowPlaying { nowPlayingCard(track) }
            if !viewModel.liveActivities.isEmpty { liveCard }
            if !activeTransfers.isEmpty { transfersCard }
            clipsCard
            footer
        }
        .padding(12)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .background(FuseColor.bg)
        .background(GeometryReader { FitMenuWindow(height: $0.size.height) })
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(FuseColor.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .background(FuseColor.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        Label("Drop to send to \(viewModel.peerName ?? "your phone")", systemImage: "arrow.up.doc")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(FuseColor.accent),
                    )
                    .padding(6)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            viewModel.sendFiles(files)
            return true
        } isTargeted: { dropTargeted = $0 }
        // A link coming up ends the search, whichever way it came.
        .onChange(of: viewModel.connected) { connected in
            if !connected.isEmpty { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { search = .idle } }
        }
        // Gives up after 12 s: long enough for a dial and a TLS-free LAN handshake, short
        // enough that someone watching the radar is not left wondering.
        .task(id: search) {
            guard search == .searching else { return }
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard !Task.isCancelled, search == .searching, viewModel.connected.isEmpty else { return }
            withAnimation { search = .notFound }
        }
    }

    // MARK: - Sections

    private var header: some View {
        let linked = !viewModel.connected.isEmpty
        return HStack(spacing: 8) {
            Image(nsImage: FuseMenuIcon.image(linked: true))
                .renderingMode(.template)
                .foregroundStyle(FuseColor.ink)
            Text("FuseOS")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(FuseColor.ink)
            Text(linked ? "Linked" : "Not linked")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(linked ? FuseColor.accent : FuseColor.muted)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background((linked ? FuseColor.accent : FuseColor.muted).opacity(0.14), in: Capsule())
            Spacer(minLength: 0)
            Button {
                openMain()
            } label: {
                Image(systemName: "macwindow")
                    .font(.system(size: 13))
            }
            .buttonStyle(IconButtonStyle())
            .help("Open FuseOS")
        }
        .padding(.horizontal, 2)
    }

    /// The link, live: this Mac and the phone, a spark crossing whenever anything does.
    private var deviceCard: some View {
        let peer = viewModel.peers.first { viewModel.connected.contains($0.id) } ?? viewModel.peers.first
        let presence = peer.map { viewModel.onlineState(for: $0) }
        let linked = peer.map { viewModel.isConnected($0) } ?? false
        return Card {
            VStack(spacing: 10) {
                HStack(spacing: 0) {
                    endpoint("laptopcomputer", lit: true)
                    LiveFilament(linked: linked, pulse: viewModel.linkPulse, stream: viewModel.streamToPhone)
                        .frame(height: 20)
                        .padding(.horizontal, 6)
                    endpoint("iphone.gen3", lit: linked)
                }
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(peer?.name ?? "No phone yet")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(FuseColor.ink)
                            .lineLimit(1)
                        Text(statusLine(linked: linked, online: presence?.online ?? false, hasPeer: peer != nil))
                            .font(.system(size: 11))
                            .foregroundStyle(FuseColor.muted)
                            .monospacedDigit()
                    }
                    Spacer(minLength: 0)
                    if let battery = viewModel.phoneStatus?.battery ?? presence?.battery {
                        BatteryRing(percent: battery, charging: viewModel.phoneStatus?.charging ?? false)
                    }
                }
            }
        }
    }

    private func endpoint(_ symbol: String, lit: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(lit ? FuseColor.accent : FuseColor.muted)
            .frame(width: 38, height: 38)
            .background(Circle().fill(FuseColor.accent.opacity(lit ? 0.14 : 0.05)))
    }

    /// The four things people open the popover to do with the phone.
    private var actionsRow: some View {
        HStack(spacing: 8) {
            quickAction("Open link", "safari.fill") {
                if let url = viewModel.clipboardLink { viewModel.openOnPhone(url) }
            }
            .disabled(viewModel.clipboardLink == nil)
            .help("Opens the link you copied on this Mac in your phone's browser")
            quickAction("Mirror", "rectangle.on.rectangle") {
                openMain()
                viewModel.screen.start()
            }
            quickAction("Send file", "arrow.up.doc.fill") { chooseFiles() }
        }
    }

    private func quickAction(_ title: String, _ symbol: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(FuseColor.accent)
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(FuseColor.ink)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(FuseColor.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(FuseColor.outline.opacity(0.5), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func nowPlayingCard(_ track: NowPlaying) -> some View {
        Card {
            HStack(spacing: 10) {
                Group {
                    if let data = track.artwork, let image = NSImage(data: data) {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "music.note").foregroundStyle(FuseColor.accent)
                            .frame(maxWidth: .infinity, maxHeight: .infinity).background(FuseColor.accent.opacity(0.12))
                    }
                }
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(FuseColor.ink).lineLimit(1)
                    Text(track.artist.isEmpty ? track.appName : track.artist)
                        .font(.system(size: 11)).foregroundStyle(FuseColor.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button { viewModel.media.playPause() } label: {
                    Image(systemName: track.playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 30, height: 30).background(Circle().fill(FuseColor.accent))
                }
                .buttonStyle(.plain)
                Button { viewModel.media.next() } label: {
                    Image(systemName: "forward.fill").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(FuseColor.ink).frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var liveCard: some View {
        Card(title: "Live on your phone") {
            VStack(spacing: 8) {
                ForEach(viewModel.liveActivities.values.sorted { $0.postedAt > $1.postedAt }) { activity in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(activity.title.isEmpty ? activity.appName : activity.title)
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(FuseColor.ink).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(activity.appName).font(.system(size: 10.5)).foregroundStyle(FuseColor.muted).lineLimit(1)
                        }
                        if let progress = activity.progress {
                            ProgressBar(fraction: progress)
                        }
                    }
                }
            }
        }
    }

    /// Nothing linked: a way to link, and what the search is finding while it runs.
    private var connectCard: some View {
        Card {
            VStack(spacing: 12) {
                switch search {
                case .idle:
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(FuseColor.muted.opacity(0.12))
                                .frame(width: 42, height: 42)
                            Image(systemName: "iphone.slash")
                                .font(.system(size: 19))
                                .foregroundStyle(FuseColor.muted)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Not connected")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(FuseColor.ink)
                            Text("Find your phone on this Wi-Fi")
                                .font(.system(size: 10.5))
                                .foregroundStyle(FuseColor.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    Button { startSearch() } label: {
                        Label("Connect", systemImage: "dot.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PillButtonStyle(prominent: true))

                case .searching:
                    Radar()
                        .frame(height: 96)
                    Text("Looking for your devices…")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FuseColor.ink)
                    foundList

                case .notFound:
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Couldn't reach your phone", systemImage: "exclamationmark.magnifyingglass")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(FuseColor.ink)
                        tip("Open FuseOS on your phone and sign in to the same account.")
                        tip("Put both devices on the same Wi-Fi network.")
                        tip("Allow FuseOS on the local network in System Settings → Privacy & Security.")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    foundList
                    Button { startSearch() } label: {
                        Label("Try again", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PillButtonStyle(prominent: true))
                }
            }
        }
    }

    /// The account's other devices, and what the search can say about each right now.
    @ViewBuilder
    private var foundList: some View {
        if !viewModel.peers.isEmpty {
            VStack(spacing: 6) {
                ForEach(viewModel.peers) { peer in
                    let presence = viewModel.onlineState(for: peer)
                    let linked = viewModel.isConnected(peer)
                    HStack(spacing: 8) {
                        Image(systemName: peer.platform == "android" ? "iphone.gen3" : "laptopcomputer")
                            .foregroundStyle(presence.online ? FuseColor.accent : FuseColor.muted)
                            .frame(width: 18)
                        Text(peer.name)
                            .font(.system(size: 12))
                            .foregroundStyle(FuseColor.ink)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if linked {
                            Label("Linked", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(FuseColor.accent)
                        } else if presence.online {
                            HStack(spacing: 5) {
                                ProgressView().controlSize(.mini)
                                Text("connecting").font(.system(size: 10.5))
                            }
                            .foregroundStyle(FuseColor.muted)
                        } else {
                            Text("offline")
                                .font(.system(size: 10.5))
                                .foregroundStyle(FuseColor.muted)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(FuseColor.surfaceAlt.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func tip(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle().fill(FuseColor.accent).frame(width: 4, height: 4)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(FuseColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func startSearch() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { search = .searching }
        Task { await viewModel.connect() }
    }

    private var transfersCard: some View {
        Card(title: "Files") {
            VStack(spacing: 8) {
                ForEach(activeTransfers) { t in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Image(systemName: t.outgoing ? "arrow.up.circle" : "arrow.down.circle")
                                .foregroundStyle(FuseColor.accent)
                            Text(t.name)
                                .font(.system(size: 12))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                            Button {
                                viewModel.cancelTransfer(t.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(FuseColor.muted)
                            .help("Cancel")
                        }
                        ProgressBar(fraction: Double(t.bytes) / Double(max(t.total, 1)))
                    }
                }
            }
        }
    }

    private var clipsCard: some View {
        Card(title: "Recent clips", trailing: viewModel.history.isEmpty ? nil : "\(viewModel.history.count)") {
            if viewModel.history.isEmpty {
                Text("Copy something on either device and it shows up here.")
                    .font(.system(size: 12))
                    .foregroundStyle(FuseColor.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 2) {
                    // Three keeps the popover within a small MacBook's screen even with music,
                    // a live activity and a file showing; the window has the rest.
                    ForEach(viewModel.history.prefix(3)) { entry in
                        ClipRowButton(
                            entry: entry,
                            peerName: viewModel.peerName,
                            copied: copiedId == entry.id,
                            // Anything can go (back) to the phone: its clipboard has moved on since.
                            onSend: { viewModel.sendToPhone(entry) },
                        ) {
                            viewModel.copyToClipboard(entry)
                            withAnimation(.easeOut(duration: 0.15)) { copiedId = entry.id }
                            Task {
                                try? await Task.sleep(nanoseconds: 1_300_000_000)
                                if copiedId == entry.id { withAnimation { copiedId = nil } }
                            }
                        }
                        .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                    }
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.8), value: viewModel.history.first?.id)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                openMain()
            } label: {
                Label("Open FuseOS", systemImage: "macwindow")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PillButtonStyle())

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(PillButtonStyle())
            .help("Quit FuseOS")
        }
        .overlay(alignment: .top) {
            if let notice = viewModel.fileNotice {
                Text(notice)
                    .font(.system(size: 11))
                    .foregroundStyle(FuseColor.error)
                    .offset(y: -18)
            }
        }
    }

    // MARK: - Helpers

    private var activeTransfers: [TransferProgress] { viewModel.transfers.filter { !$0.finished } }

    private func statusLine(linked: Bool, online: Bool, hasPeer: Bool) -> String {
        if !hasPeer { return SessionStore.shared.email.map { "Sign in on your phone as \($0)" } ?? "Sign in on your phone to link it" }
        if linked {
            if let latency = viewModel.syncLatency { return "Linked · direct · \(latency.lastMs) ms" }
            return "Linked · direct"
        }
        return online ? "Online · connecting…" : "Offline"
    }

    private func openMain() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        viewModel.sendFiles(panel.urls)
    }
}

// MARK: - Pieces

/// Three rings pulsing out from the Mac: the search, running.
/// Keeps the popover's window fitted to its content, its top under the menu bar.
///
/// `MenuBarExtra` sizes its window once, when it opens. Content that changes while it is
/// open — a link coming up, a card going away — was clipped when it grew and, when it
/// shrank, left the window hanging below the menu bar with a strip of nothing above it.
private struct FitMenuWindow: NSViewRepresentable {
    let height: CGFloat

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        // After this layout pass: resizing the window from inside it would re-enter it.
        DispatchQueue.main.async {
            guard let window = view.window, height > 0 else { return }
            let content = NSRect(x: 0, y: 0, width: window.contentLayoutRect.width, height: height)
            let size = window.frameRect(forContentRect: content).size
            // The content's top just under the menu bar, where the popover opens. The window
            // reaches higher than its content (a strip the system tucks behind the menu bar),
            // so the frame's own top is not the anchor.
            let chrome = window.frame.height - window.contentLayoutRect.maxY
            let top = (window.screen?.visibleFrame.maxY).map { $0 + chrome } ?? window.frame.maxY
            let frame = NSRect(x: window.frame.minX, y: top - size.height, width: window.frame.width, height: size.height)
            guard abs(window.frame.height - frame.height) > 0.5 || abs(window.frame.maxY - top) > 0.5 else { return }
            window.setFrame(frame, display: true)
        }
    }
}

private struct Radar: View {
    var body: some View {
        ZStack {
            Ripples()
            ZStack {
                Circle().fill(FuseColor.accent.opacity(0.15)).frame(width: 40, height: 40)
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(FuseColor.accent)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// A section of the popover: a rounded surface with an optional small-caps title.
private struct Card<Content: View>: View {
    var title: String?
    var trailing: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                HStack {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(FuseColor.ink)
                    Spacer()
                    if let trailing {
                        Text(trailing)
                                .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(FuseColor.muted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(FuseColor.surfaceAlt, in: Capsule())
                    }
                }
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FuseColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(FuseColor.outline.opacity(0.5), lineWidth: 1),
        )
    }
}

/// One clip: click to put it back on the clipboard; it says "Copied" for a moment after.
private struct ClipRowButton: View {
    let entry: ClipEntry
    let peerName: String?
    let copied: Bool
    var onSend: (() -> Bool)?
    let action: () -> Void
    @State private var hovering = false
    /// What the last Send did — true sent, false not linked — shown for a moment.
    @State private var sent: Bool?

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let data = entry.imageData, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 26, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 11))
                        .foregroundStyle(FuseColor.accent)
                        .frame(width: 26, height: 26)
                        .background(FuseColor.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(summary)
                        .font(.system(size: 12))
                        .foregroundStyle(FuseColor.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(entry.fromSelf ? "Copied here" : "From \(peerName ?? "your phone")")
                        .font(.system(size: 10.5))
                        .foregroundStyle(FuseColor.muted)
                }
                Spacer(minLength: 0)
                if copied {
                    Label("Copied", systemImage: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(FuseColor.accent)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else if let sent {
                    SendResultLabel(sent: sent, size: 10)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else if hovering, let onSend {
                    Button {
                        let ok = onSend()
                        withAnimation(.easeOut(duration: 0.15)) { sent = ok }
                        Task {
                            try? await Task.sleep(nanoseconds: 1_600_000_000)
                            withAnimation { sent = nil }
                        }
                    } label: {
                        Label("Send", systemImage: "arrow.up.right")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .frame(height: 22)
                            .background(Capsule().fill(FuseColor.accent))
                    }
                    .buttonStyle(.plain)
                    .help("Send to \(peerName ?? "your phone")")
                    .transition(.opacity)
                } else {
                    Text(entry.at, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                        .font(.system(size: 10.5))
                        .foregroundStyle(FuseColor.muted)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(hovering ? FuseColor.surfaceAlt : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovering = inside } }
        .help("Copy to this Mac's clipboard")
    }

    /// Newlines would make a one-line row render as a stray fragment.
    private var summary: String {
        if entry.isImage {
            guard let rep = entry.imageData.flatMap(NSImage.init(data:))?.representations.first, rep.pixelsWide > 0 else { return "Image" }
            return "Image · \(rep.pixelsWide) × \(rep.pixelsHigh)"
        }
        return (entry.text ?? "").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
    }
}

private struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(FuseColor.muted)
            .frame(width: 26, height: 26)
            .background(FuseColor.surfaceAlt.opacity(configuration.isPressed ? 1 : 0.6), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct PillButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(prominent ? Color.white : FuseColor.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                prominent ? AnyShapeStyle(FuseColor.accent) : AnyShapeStyle(FuseColor.surface),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous),
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(FuseColor.outline.opacity(prominent ? 0 : 0.6), lineWidth: 1),
            )
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
    }
}
