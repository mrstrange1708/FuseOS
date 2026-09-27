import CryptoKit
import Foundation

/// The phone's Bluetooth beacon value: HMAC-SHA256(key, window) cut to 8 bytes, where the
/// window is the unix time in ten-minute steps as an 8-byte big-endian integer. Only a
/// holder of the key recognises it, and it changes every ten minutes, so nobody else can
/// follow the phone by its beacon. Must match `BeaconToken` on Android byte for byte.
public enum BeaconToken {
    public static let windowSeconds: TimeInterval = 600

    public static func window(at date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 / windowSeconds).rounded(.down))
    }

    public static func token(key: Data, window: Int64) -> Data {
        var bigEndian = window.bigEndian
        let message = Data(bytes: &bigEndian, count: 8)
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: key))
        return Data(mac).prefix(8)
    }

    /// The values a phone may be advertising now: this window's, and the last one's, so a
    /// clock a little behind still matches.
    public static func current(key: Data, at date: Date = Date()) -> Set<Data> {
        let w = window(at: date)
        return [token(key: key, window: w), token(key: key, window: w - 1)]
    }
}
