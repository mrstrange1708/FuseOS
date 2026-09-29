import Foundation

/// When to lock the Mac because the phone has left.
///
/// Two signals, both required. Bluetooth must say the phone is **far** — heard, then weak
/// or silent — because that is the only one that measures distance: a Wi-Fi link drops for
/// many reasons with the phone on the desk (the OS pausing the app, a network blip), and
/// locking on that alone locked people out while they sat there. And the phone's app must
/// be provably **alive** — still linked over Wi-Fi (walked to another room), or online via
/// the server (left on mobile data) — because a beacon also goes silent when the app is
/// killed or the battery dies next to the Mac, and that is not a reason to lock anyone out.
public enum AwayLock {
    /// How long the phone must stay away before locking: long enough to ride out a Wi-Fi
    /// blip or a lift, short enough to matter.
    public static let grace: TimeInterval = 20

    public static func shouldLock(enabled: Bool, bluetoothFar: Bool, linkedNow: Bool, phoneOnlineViaServer: Bool) -> Bool {
        enabled && bluetoothFar && (linkedNow || phoneOnlineViaServer)
    }
}
