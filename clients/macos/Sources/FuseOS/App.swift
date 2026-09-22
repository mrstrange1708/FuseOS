import SwiftUI
import AppKit
import FuseOSCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set once the app's scenes exist. Services can arrive before that (a Finder
    /// "Send to Phone" that launched the app), so those wait in `pending` until it is.
    @MainActor var dashboard: DashboardViewModel? {
        didSet {
            guard let dashboard, !pending.isEmpty else { return }
            dashboard.sendFiles(pending)
            pending = []
        }
    }

    @MainActor private var pending: [URL] = []

    /// Closing the window no longer quits: the menu bar item can reopen it and quit, and
    /// sync has to outlive the window for a continuity app to be worth anything.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The Mac side of "share to the other device": Finder's right-click → Services.
        // A Share-sheet extension would need a sandbox and an App Group signed with a
        // paid Team ID; a Service needs neither and lands in the same place.
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    /// Services → "Send to Phone with FuseOS" on files in Finder (`NSServices` in Info.plist).
    @MainActor @objc func sendFiles(
        _ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>,
    ) {
        let urls = (pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        guard !urls.isEmpty else { return }
        if let dashboard { dashboard.sendFiles(urls) } else { pending += urls }
    }

    /// Services → "Send Text to Phone with FuseOS" on selected text in any app. Putting it on
    /// the pasteboard is enough: clipboard sync sends every copy made on this Mac.
    @MainActor @objc func sendText(
        _ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>,
    ) {
        guard let text = pboard.string(forType: .string), !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

@main
struct FuseOSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = SessionStore.shared
    @StateObject private var dashboard = DashboardViewModel()
    /// Onboarding runs once. After the first Continue, launches go straight to the
    /// dashboard — which shows the same connection status, so nothing is hidden by skipping.
    @AppStorage("hasCompletedConnect") private var hasCompletedConnect = false

    var body: some Scene {
        WindowGroup("FuseOS", id: "main") {
            Group {
                if session.token == nil {
                    AuthView()
                } else if session.deviceName == nil {
                    DeviceNameView()
                } else if hasCompletedConnect {
                    ShellView(viewModel: dashboard)
                } else {
                    ConnectView(viewModel: dashboard) { hasCompletedConnect = true }
                }
            }
            .environmentObject(session)
            .frame(minWidth: 420, minHeight: 560)
            .onAppear { appDelegate.dashboard = dashboard }
        }
        // Not .contentSize: the signed-in shell is a split view the user resizes, while
        // the auth screens are a fixed column. Pinning the window to its content would
        // let the narrow screens dictate the size of the wide one.
        .windowResizability(.automatic)

        // The menu bar item is the app's real home on a Mac: continuity is something you
        // reach for mid-task, and hunting for a window to paste yesterday's link defeats
        // the point. Only shown once signed in — there is nothing to offer before that.
        MenuBarExtra {
            if session.token == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sign in to link your phone.")
                        .font(.system(size: 12))
                    Button("Open FuseOS") { openMainWindow() }
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                }
                .padding(14)
            } else {
                MenuBarContent(viewModel: dashboard)
            }
        } label: {
            // The FuseOS mark, filled on the right when a device is linked.
            Image(nsImage: FuseMenuIcon.image(linked: !dashboard.connected.isEmpty))
                .onAppear { appDelegate.dashboard = dashboard }
        }
        .menuBarExtraStyle(.window)
    }

    /// `openWindow` is unavailable outside a scene's content, so the pre-login menu goes
    /// through AppKit instead of duplicating the environment plumbing for two buttons.
    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
    }
}
