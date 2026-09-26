import Foundation

/// When to lock the Mac because the phone has left.
///
/// "Left" means the direct LAN link to the phone is gone while the server still sees the
/// phone online: it is somewhere else, on mobile data or another Wi-Fi. A phone that went
/// quiet — asleep, app killed, battery dead — drops off the server too, and that is not a
/// reason to lock anyone out.
public enum AwayLock {
    /// How long the phone must stay away before locking: long enough to ride out a Wi-Fi
    /// blip or a lift, short enough to matter.
    public static let grace: TimeInterval = 20

    public static func shouldLock(enabled: Bool, linkedNow: Bool, phoneOnlineViaServer: Bool) -> Bool {
        enabled && !linkedNow && phoneOnlineViaServer
    }
}
