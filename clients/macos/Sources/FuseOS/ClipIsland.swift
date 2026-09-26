import AppKit
import SwiftUI
import FuseOSCore

/// The Dynamic Island: a black shape that grows out of the notch to show what just crossed
/// between the devices — a clip, an image, a file with its progress.
///
/// Sync is invisible by nature — content simply appears on the other device — which leaves
/// the user with no way to tell "it worked" apart from "it is broken". The island is that
/// signal, and it is deliberately the *only* one: it shows itself for a moment and gets out
/// of the way, never a window to manage.
///
/// On a notched Mac it starts exactly the notch's size and swells out of it; elsewhere it
/// drops from the top-centre of the screen the same way. It is an `NSPanel` rather than a
/// SwiftUI window because it has to sit above full-screen apps, across every Space, and
/// never steal focus from whatever the user is typing into.
@MainActor
final class ClipIsland {
    private let model = IslandModel()
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    /// Shows one clip. A second event replaces the first rather than queueing — a backlog
    /// of stale animations is noise, and only the newest event is still true.
    func present(_ entry: ClipEntry, peerName: String?) {
        show(.clip(entry), peerName: peerName, restart: true)
        scheduleDismiss(after: Self.visibleSeconds)
    }

    /// Shows a file transfer and keeps it up to date. The same transfer updating in place
    /// does not re-animate; it stays open while bytes move and closes shortly after the end.
    func present(_ transfer: TransferProgress, peerName: String?) {
        // A cancel is the user's own doing; announcing it back to them is noise.
        if transfer.state == .cancelled {
            if case let .transfer(current) = model.content, current.id == transfer.id { dismiss() }
            return
        }
        let same: Bool = {
            if case let .transfer(current) = model.content { return current.id == transfer.id }
            return false
        }()
        show(.transfer(transfer), peerName: peerName, restart: !same || panel?.isVisible != true)
        if transfer.finished {
            scheduleDismiss(after: Self.visibleSeconds)
        } else {
            dismissTask?.cancel()
        }
    }

    /// A copy waiting on the user: the island is the "send it?" prompt, and its button sends.
    func offer(_ offer: ClipOffer, peerName: String?) {
        show(.offer(offer), peerName: peerName, restart: true)
        scheduleDismiss(after: Self.notificationSeconds)
    }

    /// A notification from the phone: the app, and what it said.
    func present(_ notification: PhoneNotification) {
        show(.notification(notification), peerName: nil, restart: true)
        scheduleDismiss(after: Self.notificationSeconds)
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) { model.expanded = false }
        // Ordering out mid-animation would cut it off, so the panel outlives it briefly.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 320_000_000)
            guard self?.model.expanded == false else { return }
            self?.panel?.orderOut(nil)
        }
    }

    private func show(_ content: IslandModel.Content, peerName: String?, restart: Bool) {
        let panel = panel ?? makePanel()
        self.panel = panel
        model.content = content
        model.peerName = peerName
        position(panel)
        panel.orderFrontRegardless()
        guard restart else { return }
        // Collapsing to the notch first is what makes a repeat event read as new rather
        // than a static badge that never changed.
        model.expanded = false
        DispatchQueue.main.async { [model] in
            withAnimation(.spring(response: 0.46, dampingFraction: 0.74)) { model.expanded = true }
        }
    }

    private func scheduleDismiss(after seconds: Double) {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
        )
        panel.isFloatingPanel = true
        // Above the menu bar, which is where the notch is.
        panel.level = .statusBar + 1
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false // the SwiftUI shape draws its own, shaped to its corners
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        // Follows the user across Spaces and into full-screen; a HUD that only exists on
        // one desktop is worse than none, because you learn not to trust it.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        panel.contentView = NSHostingView(rootView: IslandView(model: model, onTap: { [weak self] in
            self?.dismiss()
        }))
        return panel
    }

    /// Pinned to the top edge, centred on the notch of whichever screen has the menu bar.
    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.frame
        model.notch = Self.notchSize(of: screen)
        panel.setFrame(
            NSRect(
                x: frame.midX - Self.panelWidth / 2,
                y: frame.maxY - Self.panelHeight,
                width: Self.panelWidth,
                height: Self.panelHeight,
            ),
            display: false,
        )
    }

    /// The notch's size, or a notch-like pill on a Mac without one so the island still has
    /// somewhere to grow from.
    private static func notchSize(of screen: NSScreen) -> CGSize {
        if #available(macOS 12.0, *), screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea
        {
            return CGSize(width: screen.frame.width - left.width - right.width, height: screen.safeAreaInsets.top)
        }
        return CGSize(width: 180, height: 26)
    }

    private static let panelWidth: CGFloat = 440
    private static let panelHeight: CGFloat = 150
    private static let visibleSeconds: Double = 2.8
    /// Longer than a clip: a notification is read, a clip only confirmed.
    private static let notificationSeconds: Double = 4.5
}

/// What the island is showing. A class so the panel can mutate it after the SwiftUI view is
/// already hosted.
@MainActor
private final class IslandModel: ObservableObject {
    enum Content {
        case clip(ClipEntry)
        case transfer(TransferProgress)
        case notification(PhoneNotification)
        case offer(ClipOffer)
    }

    @Published var content: Content?
    @Published var peerName: String?
    @Published var expanded = false
    @Published var notch = CGSize(width: 180, height: 32)
}

/// A rectangle with a flat top and rounded bottom corners, plus the two small inverted
/// "shoulders" at the top that melt it into the menu bar, the way the notch itself sits.
private struct NotchShape: Shape {
    var radius: CGFloat
    var shoulder: CGFloat = 8

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.height / 2, rect.width / 2)
        let s = shoulder
        var p = Path()
        p.move(to: CGPoint(x: rect.minX - s, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + s), control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.maxY), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - r), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + s))
        p.addQuadCurve(to: CGPoint(x: rect.maxX + s, y: rect.minY), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

private struct IslandView: View {
    @ObservedObject var model: IslandModel
    let onTap: () -> Void

    var body: some View {
        let size = model.expanded ? expandedSize : model.notch
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                NotchShape(radius: model.expanded ? 26 : model.notch.height / 2)
                    .fill(Color.black)
                    .shadow(color: .black.opacity(model.expanded ? 0.45 : 0), radius: 18, y: 10)
                if model.expanded, let content = model.content {
                    body(for: content)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 16)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var expandedSize: CGSize {
        let top = model.notch.height
        if case let .transfer(t) = model.content, !t.finished {
            return CGSize(width: 400, height: top + 84)
        }
        return CGSize(width: 380, height: top + 70)
    }

    @ViewBuilder
    private func body(for content: IslandModel.Content) -> some View {
        switch content {
        case let .clip(entry):
            row(
                icon: entry.isImage ? "photo" : "doc.on.clipboard",
                title: clipTitle(entry),
                detail: clipPreview(entry),
                thumbnail: entry.imageData.flatMap(NSImage.init(data:)),
                incoming: !entry.fromSelf,
            )
        case let .offer(offer):
            HStack(spacing: 10) {
                row(
                    icon: offer.imageData == nil ? "doc.on.clipboard" : "photo",
                    title: "Copied",
                    detail: offer.imageData == nil
                        ? (offer.text ?? "").replacingOccurrences(of: "\n", with: " ")
                        : "An image",
                    thumbnail: offer.imageData.flatMap(NSImage.init(data:)),
                    incoming: false,
                    trailing: "",
                )
                Button {
                    offer.send()
                } label: {
                    Text("Send to \(model.peerName ?? "phone")")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Capsule().fill(Color(red: 0.91, green: 0.36, blue: 0.16)))
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
        case let .notification(n):
            row(
                icon: "bell.fill",
                title: n.appName.isEmpty ? "Your phone" : n.appName,
                detail: [n.title, n.text].filter { !$0.isEmpty }.joined(separator: " · "),
                thumbnail: n.iconPNG.flatMap(NSImage.init(data:)),
                incoming: true,
            )
        case let .transfer(t):
            VStack(spacing: 10) {
                row(
                    icon: t.state == .failed ? "exclamationmark.triangle" : "doc.zipper",
                    title: transferTitle(t),
                    detail: t.name,
                    thumbnail: nil,
                    incoming: !t.outgoing,
                    trailing: t.finished ? nil : "\(percent(t))%",
                )
                if !t.finished {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12))
                            Capsule()
                                .fill(LinearGradient(
                                    colors: [Color(red: 0.91, green: 0.36, blue: 0.16), Color(red: 1, green: 0.70, blue: 0.28)],
                                    startPoint: .leading, endPoint: .trailing,
                                ))
                                .frame(width: geo.size.width * CGFloat(percent(t)) / 100)
                                .animation(.easeOut(duration: 0.25), value: percent(t))
                        }
                    }
                    .frame(height: 5)
                }
            }
        }
    }

    private func row(
        icon: String, title: String, detail: String, thumbnail: NSImage?, incoming: Bool,
        trailing: String? = nil,
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(red: 1, green: 0.48, blue: 0.27), Color(red: 0.91, green: 0.36, blue: 0.16)],
                        startPoint: .topLeading, endPoint: .bottomTrailing,
                    ))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.5))
                Text(detail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if let trailing {
                Text(trailing)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .monospacedDigit()
            } else {
                Image(systemName: incoming ? "arrow.down" : "arrow.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 1, green: 0.48, blue: 0.27))
            }
        }
    }

    private func clipTitle(_ entry: ClipEntry) -> String {
        let what = entry.isImage ? "Image" : "Copied"
        if entry.fromSelf { return model.peerName.map { "\(what) → \($0)" } ?? "\(what) · sending" }
        return model.peerName.map { "\(what) from \($0)" } ?? "\(what) from your phone"
    }

    private func clipPreview(_ entry: ClipEntry) -> String {
        if entry.isImage { return "On your clipboard" }
        // Newlines would make a one-line preview render as a stray fragment.
        return (entry.text ?? "").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
    }

    private func transferTitle(_ t: TransferProgress) -> String {
        let peer = model.peerName ?? "your phone"
        switch t.state {
        case .active: return t.outgoing ? "Sending to \(peer)" : "Receiving from \(peer)"
        case .sent: return "Waiting for \(peer)"
        case .done: return t.outgoing ? "Sent to \(peer)" : "Saved to Downloads"
        case .cancelled: return "Cancelled"
        case .failed: return "Didn't go through"
        }
    }

    private func percent(_ t: TransferProgress) -> Int {
        t.total > 0 ? min(100, t.bytes * 100 / t.total) : 0
    }
}
