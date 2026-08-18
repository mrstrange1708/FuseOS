import SwiftUI
import AppKit
import FuseOSCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    // ponytail: quitting with the last window means clipboard sync stops when the window
    // closes, which is wrong for a continuity app. Flip this to `false` once there is a
    // menu bar item to reopen the window and quit from.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
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
        WindowGroup("FuseOS") {
            Group {
                if session.token == nil {
                    AuthView()
                } else if session.deviceType == nil {
                    DeviceTypeView()
                } else if hasCompletedConnect {
                    DashboardView(viewModel: dashboard)
                } else {
                    ConnectView(viewModel: dashboard) { hasCompletedConnect = true }
                }
            }
            .environmentObject(session)
            .frame(minWidth: 420, minHeight: 600)
        }
        .windowResizability(.contentSize)
    }
}
