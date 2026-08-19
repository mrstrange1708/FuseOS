import Foundation
import ServiceManagement

/// Whether macOS starts FuseOS when the user logs in.
///
/// Continuity has to be there before you reach for it: a Mac that only syncs once you have
/// found and opened the app is a Mac you have already given up on and pasted by hand. So
/// this is enabled the first time the user reaches the signed-in app, and is a toggle
/// afterwards rather than a decision made permanently on their behalf.
///
/// `SMAppService` registers the *bundle*, which is why this only works from `FuseOS.app`
/// (built by `build-app.sh`) and silently does nothing under a bare `swift run`.
enum LaunchAtLogin {
    private static let decidedKey = "fuse.launchAtLogin.decided"

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Turns the login item on or off. Returns false when macOS refused — most often
    /// because the user has disabled the item in System Settings > General > Login Items,
    /// which is their call and not something to fight.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                // Re-registering an already-enabled service throws, and "already on" is
                // the outcome we wanted anyway.
                guard SMAppService.mainApp.status != .enabled else { return true }
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            UserDefaults.standard.set(true, forKey: decidedKey)
            return true
        } catch {
            return false
        }
    }

    /// Enables it once, the first time the user gets past onboarding. After that their
    /// choice stands — including a choice to turn it off, which this must not undo.
    static func enableOnFirstRun() {
        guard !UserDefaults.standard.bool(forKey: decidedKey) else { return }
        setEnabled(true)
    }
}
