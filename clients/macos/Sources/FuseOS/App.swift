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

    var body: some Scene {
        WindowGroup("FuseOS") {
            Group {
                if session.token == nil {
                    AuthView()
                } else if session.deviceType == nil {
                    DeviceTypeView()
                } else {
                    DashboardView()
                }
            }
            .environmentObject(session)
            .frame(minWidth: 420, minHeight: 600)
        }
        .windowResizability(.contentSize)
    }
}
