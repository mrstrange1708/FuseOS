import Foundation

/// Which of the account's devices this one links with. Mirrors Android's `DeviceTrust`.
///
/// Being on the same account is not enough: whoever learns the password could sign in on their
/// own phone and start receiving this one's copies, notifications and codes. So every device
/// keeps its own list, and a newcomer links only after the user allows it here — a decision the
/// server cannot make for them, even a compromised one.
///
/// Each approved device is pinned to its key on first sight; the same device back with a
/// different key is asked about again. The devices already on the account when this device
/// first signs in (or first runs this version) are the user's own, and are approved then.
@MainActor
public final class DeviceTrust {
    public enum Verdict: Equatable { case trusted, pending, blocked }

    private let defaults: UserDefaults
    /// deviceId → its pinned key, or "" for a device approved before its key was seen.
    private var approved: [String: String]
    private var blocked: [String: String]
    public private(set) var bootstrapped: Bool

    private static let approvedKey = "fuse.trust.approved"
    private static let blockedKey = "fuse.trust.blocked"
    private static let bootstrappedKey = "fuse.trust.bootstrapped"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        approved = defaults.dictionary(forKey: Self.approvedKey) as? [String: String] ?? [:]
        blocked = defaults.dictionary(forKey: Self.blockedKey) as? [String: String] ?? [:]
        bootstrapped = defaults.bool(forKey: Self.bootstrappedKey)
    }

    /// The first device list after sign-in (or after this update): those are the user's own.
    public func bootstrapIfNeeded(deviceIds: [String]) {
        guard !bootstrapped else { return }
        for id in deviceIds where approved[id] == nil { approved[id] = "" }
        bootstrapped = true
        save()
    }

    /// Whether to link with `deviceId` presenting `key`. Pins the key of an approved device
    /// the first time it is seen. Before the first device list, nothing is trusted yet.
    public func check(deviceId: String, key: String) -> Verdict {
        if blocked[deviceId] == key { return .blocked }
        guard let pinned = approved[deviceId] else { return .pending }
        if pinned.isEmpty {
            approved[deviceId] = key
            save()
            return .trusted
        }
        return pinned == key ? .trusted : .pending
    }

    public func approve(deviceId: String, key: String) {
        approved[deviceId] = key
        blocked[deviceId] = nil
        save()
    }

    public func block(deviceId: String, key: String) {
        blocked[deviceId] = key
        approved[deviceId] = nil
        save()
    }

    /// Signed out: the next account's devices are a different set.
    public func reset() {
        approved = [:]
        blocked = [:]
        bootstrapped = false
        save()
    }

    private func save() {
        defaults.set(approved, forKey: Self.approvedKey)
        defaults.set(blocked, forKey: Self.blockedKey)
        defaults.set(bootstrapped, forKey: Self.bootstrappedKey)
    }
}
