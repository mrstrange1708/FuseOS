import SwiftUI
import AppKit
import FuseOSCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Closing the window no longer quits: the menu bar item can reopen it and quit, and
    /// sync has to outlive the window for a continuity app to be worth anything.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
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
                } else if session.deviceType == nil {
                    DeviceTypeView()
                } else if hasCompletedConnect {
                    ShellView(viewModel: dashboard)
                } else {
                    ConnectView(viewModel: dashboard) { hasCompletedConnect = true }
                }
            }
            .environmentObject(session)
            .frame(minWidth: 420, minHeight: 560)
        }
        // Not .contentSize: the signed-in shell is a split view the user resizes, while
        // the auth screens are a fixed column. Pinning the window to its content would
        // let the narrow screens dictate the size of the wide one.
        .windowResizability(.automatic)

        // The menu bar item is the app's real home on a Mac: continuity is something you
        // reach for mid-task, and hunting for a window to paste yesterday's link defeats
        // the point. Only shown once signed in — there is nothing to offer before that.
        MenuBarExtra("FuseOS", systemImage: "link") {
            if session.token == nil {
                Button("Open FuseOS") { openMainWindow() }
                Button("Quit") { NSApplication.shared.terminate(nil) }
            } else {
                MenuBarContent(viewModel: dashboard)
            }
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
