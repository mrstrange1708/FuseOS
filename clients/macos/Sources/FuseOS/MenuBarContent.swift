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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            deviceCard
            if !activeTransfers.isEmpty { transfersCard }
            clipsCard
            notificationsCard
            footer
        }
        .padding(12)
        .frame(width: 340)
        .background(FuseColor.bg)
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
    }

    // MARK: - Sections

    private var header: some View {
        let linked = !viewModel.connected.isEmpty
        return HStack(spacing: 8) {
            Image(nsImage: FuseMenuIcon.image(linked: true))
                .renderingMode(.template)
                .foregroundStyle(FuseColor.ink)
            Text("FuseOS")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(FuseColor.ink)
            Text(linked ? "Linked" : "Not linked")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
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

    private var deviceCard: some View {
        let peer = viewModel.peers.first { viewModel.connected.contains($0.id) } ?? viewModel.peers.first
        let presence = peer.map { viewModel.onlineState(for: $0) }
        let linked = peer.map { viewModel.isConnected($0) } ?? false
        return Card {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(FuseColor.accent.opacity(linked ? 0.16 : 0.06))
                        .frame(width: 42, height: 42)
                    Image(systemName: "iphone.gen3")
                        .font(.system(size: 20))
                        .foregroundStyle(linked ? FuseColor.accent : FuseColor.muted)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(peer?.name ?? "No phone yet")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FuseColor.ink)
                        .lineLimit(1)
                    Text(statusLine(linked: linked, online: presence?.online ?? false, hasPeer: peer != nil))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(FuseColor.muted)
                }
                Spacer(minLength: 0)
                if let battery = presence?.battery {
                    BatteryRing(percent: battery)
                }
            }
        }
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
                        ProgressView(value: Double(t.bytes), total: Double(max(t.total, 1)))
                            .progressViewStyle(.linear)
                            .tint(FuseColor.accent)
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
                    // Five fits without scrolling on every screen; the window has the rest.
                    ForEach(viewModel.history.prefix(5)) { entry in
                        ClipRowButton(
                            entry: entry,
                            peerName: viewModel.peerName,
                            copied: copiedId == entry.id,
                        ) {
                            viewModel.copyToClipboard(entry)
                            withAnimation(.easeOut(duration: 0.15)) { copiedId = entry.id }
                            Task {
                                try? await Task.sleep(nanoseconds: 1_300_000_000)
                                if copiedId == entry.id { withAnimation { copiedId = nil } }
                            }
                        }
                    }
                }
            }
        }
    }

    /// The slot for the phone's notifications. Not built yet; the space is kept so the
    /// popover's shape does not change under people when it lands.
    private var notificationsCard: some View {
        Card(title: "From your phone", trailing: "Soon") {
            HStack(spacing: 10) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 14))
                    .foregroundStyle(FuseColor.muted)
                Text("Your phone's notifications will appear here.")
                    .font(.system(size: 12))
                    .foregroundStyle(FuseColor.muted)
                Spacer(minLength: 0)
            }
        }
        .opacity(0.75)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                chooseFiles()
            } label: {
                Label("Send file…", systemImage: "arrow.up.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PillButtonStyle(prominent: true))
            .disabled(viewModel.connected.isEmpty)

            Button {
                openMain()
            } label: {
                Label("Open", systemImage: "macwindow")
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
        if !hasPeer { return "Sign in on your phone to link it" }
        if linked { return "connected · direct · same Wi-Fi" }
        return online ? "online · connecting…" : "offline"
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

/// A section of the popover: a rounded surface with an optional small-caps title.
private struct Card<Content: View>: View {
    var title: String?
    var trailing: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                HStack {
                    Text(title.uppercased())
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .tracking(1.1)
                        .foregroundStyle(FuseColor.muted)
                    Spacer()
                    if let trailing {
                        Text(trailing)
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
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
    let action: () -> Void
    @State private var hovering = false

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
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(FuseColor.muted)
                }
                Spacer(minLength: 0)
                if copied {
                    Label("Copied", systemImage: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(FuseColor.accent)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else {
                    Text(entry.at, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(FuseColor.muted)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(hovering ? FuseColor.surfaceAlt : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Copy to this Mac's clipboard")
    }

    /// Newlines would make a one-line row render as a stray fragment.
    private var summary: String {
        if entry.isImage { return "Image" }
        return (entry.text ?? "").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
    }
}

/// The phone's battery as a ring, the way the menu bar's own widgets show it.
private struct BatteryRing: View {
    let percent: Int

    var body: some View {
        ZStack {
            Circle().stroke(FuseColor.outline.opacity(0.6), lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(100, percent))) / 100)
                .stroke(percent <= 20 ? FuseColor.error : FuseColor.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(percent)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(FuseColor.ink)
        }
        .frame(width: 34, height: 34)
        .help("Phone battery \(percent)%")
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
