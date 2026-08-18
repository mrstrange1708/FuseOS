import AppKit
import SwiftUI
import FuseOSCore

/// The floating island under the notch: the whole feedback layer for clipboard sync.
///
/// Sync is invisible by nature — content simply appears on the other device — which leaves
/// the user with no way to tell "it worked" apart from "it is broken". The island is that
/// signal, and it is deliberately the *only* one: a panel that shows itself for a moment
/// and gets out of the way, never a window to manage.
///
/// It is an `NSPanel` rather than a SwiftUI window because it has to sit above full-screen
/// apps, across every Space, and never steal focus from whatever the user is typing into.
@MainActor
final class ClipIsland {
    private let model = IslandModel()
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    /// Shows one clip. A second clip arriving replaces the first rather than queueing —
    /// a backlog of stale animations is noise, and only the newest clip is still true.
    func present(_ entry: ClipEntry, peerName: String?) {
        let panel = panel ?? makePanel()
        self.panel = panel

        model.entry = entry
        model.peerName = peerName
        position(panel)
        panel.orderFrontRegardless()

        // Re-animating from collapsed on every clip is what makes a repeat copy read as a
        // new event rather than a static badge that never changed.
        model.expanded = false
        withAnimation(.spring(response: 0.38, dampingFraction: 0.7)) { model.expanded = true }

        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.visibleSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        withAnimation(.easeIn(duration: 0.18)) { model.expanded = false }
        // Ordering out mid-animation would cut it off, so the panel outlives it briefly.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            self?.panel?.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
        )
        panel.isFloatingPanel = true
        // .statusBar puts it above full-screen apps, which is where a notch HUD belongs.
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false // the SwiftUI capsule draws its own, shaped to its corners
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        // Follows the user across Spaces and into full-screen; a HUD that only exists on
        // one desktop is worse than none, because you learn not to trust it.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let view = NSHostingView(rootView: IslandView(model: model, onTap: { [weak self] in
            self?.dismiss()
        }))
        panel.contentView = view
        return panel
    }

    /// Centred under the notch on whichever screen the menu bar is on.
    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.frame
        // safeAreaInsets.top is the notch on notched Macs and 0 elsewhere; adding the menu
        // bar height lands just below both, instead of hiding behind the notch on one
        // machine and floating in dead space on the other.
        let topInset = max(screen.safeAreaInsets.top, frame.height - screen.visibleFrame.maxY + frame.minY)
        panel.setFrame(
            NSRect(
                x: frame.midX - Self.width / 2,
                y: frame.maxY - topInset - Self.height - 6,
                width: Self.width,
                height: Self.height,
            ),
            display: false,
        )
    }

    private static let width: CGFloat = 380
    private static let height: CGFloat = 92
    private static let visibleSeconds: Double = 2.6
}

/// What the island is currently showing. A class so the panel can mutate it after the
/// SwiftUI view is already hosted.
@MainActor
private final class IslandModel: ObservableObject {
    @Published var entry: ClipEntry?
    @Published var peerName: String?
    @Published var expanded = false
}

private struct IslandView: View {
    @ObservedObject var model: IslandModel
    let onTap: () -> Void

    var body: some View {
        VStack {
            if let entry = model.entry {
                capsule(for: entry)
                    .scaleEffect(model.expanded ? 1 : 0.82, anchor: .top)
                    .opacity(model.expanded ? 1 : 0)
                    .offset(y: model.expanded ? 0 : -14)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onTapGesture(perform: onTap)
    }

    private func capsule(for entry: ClipEntry) -> some View {
        HStack(spacing: 12) {
            icon(for: entry)

            VStack(alignment: .leading, spacing: 2) {
                Text(title(for: entry))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(preview(for: entry))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)

            if let thumbnail = thumbnail(for: entry) {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 340)
        // Glass: the material carries the blur, the stroke keeps the edge legible against
        // a bright desktop, where a pure material capsule dissolves into the wallpaper.
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1),
        )
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
    }

    private func icon(for entry: ClipEntry) -> some View {
        ZStack {
            Circle()
                .fill(FuseColor.accent.opacity(0.18))
                .frame(width: 34, height: 34)
            Image(systemName: entry.fromSelf ? "arrow.up" : "arrow.down")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(FuseColor.accent)
        }
    }

    private func title(for entry: ClipEntry) -> String {
        let what = entry.isImage ? "Image" : "Copied"
        if entry.fromSelf {
            return model.peerName.map { "\(what) → \($0)" } ?? "\(what) · sending"
        }
        return model.peerName.map { "\(what) from \($0)" } ?? "\(what) from your phone"
    }

    private func preview(for entry: ClipEntry) -> String {
        if entry.isImage { return "On your clipboard" }
        // Newlines would make a one-line preview render as a stray fragment.
        return (entry.text ?? "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    private func thumbnail(for entry: ClipEntry) -> NSImage? {
        entry.imageData.flatMap(NSImage.init(data:))
    }
}
