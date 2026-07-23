import SwiftUI
import AppKit

/// Run via `swift run` this is a bare executable, not a bundled `.app`, so macOS
/// launches it as a background/accessory process whose window never becomes key —
/// which is why clicks and keyboard input silently do nothing. Promoting it to a
/// regular foreground app and activating it makes the login screen interactive.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

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
