import Foundation

/// When to lock the Mac because the phone has left.
///
/// Bluetooth is the only signal that measures distance, but it is the flaky one: Android
/// throttles a background beacon, so a phone lying on the desk goes quiet or reads weak.
/// Wi-Fi measures nothing, but it is steady. So neither locks alone — they have to agree:
///
/// - **Still linked over Wi-Fi** (another room, same network): Bluetooth's "far" is only
///   believed after the Mac asks the phone over the link to beacon at full power
///   (`BeaconCheck`), the phone says its beacon is on, and the Mac *still* hears it far.
/// - **Link down:** only if the phone is online on *another* network — it left. On this
///   Wi-Fi with the link down, the app was paused next to the Mac as often as not, and
///   nothing can check; a phone gone quiet everywhere (asleep, killed, dead battery) is no
///   reason to lock anyone out either.
public enum AwayLock {
    /// How long the phone must stay away after its link drops: long enough to ride out a
    /// Wi-Fi blip or a lift, short enough to matter.
    public static let grace: TimeInterval = 20
    /// How long the phone beacons at full power when asked; the Mac decides at the end.
    public static let checkWindow: TimeInterval = 15

    public static func shouldLock(enabled: Bool, bluetoothFar: Bool, linkedNow: Bool,
                                  checkConfirmedFar: Bool, phoneOnAnotherNetwork: Bool) -> Bool {
        guard enabled, bluetoothFar else { return false }
        return linkedNow ? checkConfirmedFar : phoneOnAnotherNetwork
    }

    /// Whether two "ip:port" LAN addresses are on the same network.
    /// ponytail: same /24 — what home and office Wi-Fi hand out; a wider subnet would read
    /// as "another network" and fall back to the Bluetooth check's stricter path.
    public static func sameNetwork(_ a: String?, _ b: String?) -> Bool {
        func prefix(_ address: String?) -> ArraySlice<Substring>? {
            let octets = address?.split(separator: ":").first?.split(separator: ".")
            guard let octets, octets.count == 4 else { return nil }
            return octets.prefix(3)
        }
        guard let left = prefix(a), let right = prefix(b) else { return false }
        return left == right
    }
}
