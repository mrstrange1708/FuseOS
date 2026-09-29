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

    /// Set by the menu bar label, the one view that is alive from launch. AppKit cannot
    /// recreate a closed SwiftUI window by itself, so reopening goes through SwiftUI's own
    /// `openWindow` — for a `Window` scene that brings back the one window, never a second.
    @MainActor var openMain: (() -> Void)?

    /// The one way to show the main window: Dock click, menu bar, or a Service.
    @MainActor func showMainWindow() {
        // Into the Dock first, so the window arrives as a normal app window, not a stray.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let openMain {
            openMain()
        } else {
            NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
        }
    }

    /// A Dock click. Without this the menu bar item's own window counts as "a visible
    /// window", so AppKit decides there is nothing to reopen and the click does nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { showMainWindow() }
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DockIcon.watch()
        if let directory = DemoMode.directory {
            Task { @MainActor in await DemoMode.snapshot(to: directory) }
        }
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

    /// Services → "Open Link on Phone with FuseOS" on a selected link or text containing one.
    @MainActor @objc func openLinkOnPhone(
        _ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>,
    ) {
        let text = pboard.string(forType: .URL) ?? pboard.string(forType: .string) ?? ""
        guard let url = PhoneCommands.firstLink(in: text) else { return }
        dashboard?.openOnPhone(url)
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
        // A `Window`, not a `WindowGroup`: FuseOS has one main window, and `openWindow` on a
        // group opens another copy each time the menu bar's Open is clicked.
        Window("FuseOS", id: "main") {
            Group {
                if DemoMode.isOn {
                    ShellView(viewModel: dashboard)
                } else if session.token == nil {
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
        // The glass bar sits where the title would; the traffic lights stay.
        .windowStyle(.hiddenTitleBar)

        // The menu bar item is the app's real home on a Mac: continuity is something you
        // reach for mid-task, and hunting for a window to paste yesterday's link defeats
        // the point. Only shown once signed in — there is nothing to offer before that.
        MenuBarExtra {
            if session.token == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sign in to link your phone.")
                        .font(.system(size: 12))
                    Button("Open FuseOS") { appDelegate.showMainWindow() }
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                }
                .padding(14)
            } else {
                MenuBarContent(viewModel: dashboard)
            }
        } label: {
            // The FuseOS mark, filled on the right when a device is linked.
            MenuIconLabel(linked: !dashboard.connected.isEmpty) {
                appDelegate.dashboard = dashboard
                appDelegate.openMain = $0
            }
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu bar icon. It is a view of its own only to reach `openWindow`, which exists in a
/// view's environment and not in the `App`, and hand it to the delegate.
private struct MenuIconLabel: View {
    let linked: Bool
    let register: (@escaping () -> Void) -> Void
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: FuseMenuIcon.image(linked: linked))
            .onAppear { register { openWindow(id: "main") } }
    }
}

/// Whether FuseOS has a Dock icon: always while its window is open — an open window with
/// no Dock icon reads as a broken app, and ⌘Tab can't reach it — and, once the window is
/// closed, only if the user keeps it there ("Show in Dock"). The menu bar item stays either
/// way, so a hidden icon never leaves the app unreachable.
enum DockIcon {
    static let key = "showInDock"

    /// Kept in the Dock even with the window closed.
    static var isPinned: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }

    private static var observers: [NSObjectProtocol] = []

    @MainActor static func update() {
        // The menu bar's own window is a panel and never counts.
        let windowOpen = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain && !($0 is NSPanel) }
            || NSApp.windows.contains { $0.isMiniaturized }
        let wanted: NSApplication.ActivationPolicy = isPinned || windowOpen ? .regular : .accessory
        guard NSApp.activationPolicy() != wanted else { return }
        NSApp.setActivationPolicy(wanted)
    }

    /// Follows the main window opening and closing for the life of the app.
    @MainActor static func watch() {
        let center = NotificationCenter.default
        // A closing window is still visible when it says so; look once it has gone.
        let later: (Notification) -> Void = { _ in DispatchQueue.main.async { MainActor.assumeIsolated { update() } } }
        for name in [NSWindow.didBecomeMainNotification, NSWindow.willCloseNotification,
                     NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main, using: later))
        }
        update()
    }
}
