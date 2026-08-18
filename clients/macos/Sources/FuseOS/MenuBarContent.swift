import SwiftUI
import FuseOSCore

/// The menu bar item: link state and the last few clips, without opening the window.
///
/// This is the app's real home on a Mac. Continuity is something you reach for mid-task —
/// you want yesterday's copied link while writing an email, not to go window-hunting for
/// it. Everything here is one click from the menu bar, and the window stays for the
/// things that need room.
struct MenuBarContent: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 6)

            if viewModel.history.isEmpty {
                Text("Nothing copied yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(FuseColor.muted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                Text("RECENT")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(FuseColor.muted)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)

                // Six fits without scrolling on every screen size; the window has the
                // full list and the time filters.
                ForEach(viewModel.history.prefix(6)) { entry in
                    Button {
                        viewModel.copyToClipboard(entry)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: entry.isImage ? "photo" : "text.alignleft")
                                .font(.system(size: 10))
                                .foregroundStyle(FuseColor.accent)
                                .frame(width: 14)
                            Text(summary(of: entry))
                                .font(.system(size: 12))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
            }

            Divider().padding(.vertical, 6)

            Button("Open FuseOS") { openWindow(id: "main") }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
        }
        .padding(.vertical, 8)
        .frame(width: 280)
    }

    private var header: some View {
        let connected = !viewModel.connected.isEmpty
        let peer = viewModel.peers.first { viewModel.connected.contains($0.id) }
        return HStack(spacing: 8) {
            Circle()
                .fill(connected ? FuseColor.accent : FuseColor.muted)
                .frame(width: 7, height: 7)
            Text(connected ? "Linked to \(peer?.name ?? "your phone")" : "Not linked")
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
    }

    /// Newlines would make a one-line menu row render as a stray fragment.
    private func summary(of entry: ClipEntry) -> String {
        if entry.isImage { return "Image" }
        return (entry.text ?? "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
