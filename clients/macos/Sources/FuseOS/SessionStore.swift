import Foundation

/// Persists the signed-in session (token + email), the chosen device type, and
/// this install's stable device identity (key + server device id).
///
/// Dev note: for production, the token belongs in the Keychain, not UserDefaults.
@MainActor
final class SessionStore: ObservableObject {
    static let shared = SessionStore()

    @Published private(set) var token: String?
    @Published private(set) var email: String?
    @Published private(set) var deviceType: String?
    @Published private(set) var deviceId: String?

    private let defaults = UserDefaults.standard
    private let tokenKey = "fuse.token"
    private let emailKey = "fuse.email"
    private let deviceTypeKey = "fuse.deviceType"
    private let deviceIdKey = "fuse.deviceId"
    private let deviceKeyKey = "fuse.deviceKey"

    private init() {
        token = defaults.string(forKey: tokenKey)
        email = defaults.string(forKey: emailKey)
        deviceType = defaults.string(forKey: deviceTypeKey)
        deviceId = defaults.string(forKey: deviceIdKey)
    }

    /// Stable per-install identifier used as the device's public key (a random
    /// stand-in until the LAN data plane brings real keypairs). Generated once.
    var deviceKey: String {
        if let existing = defaults.string(forKey: deviceKeyKey) { return existing }
        var bytes = [UInt8](repeating: 0, count: 32)
        for i in bytes.indices { bytes[i] = UInt8.random(in: 0 ... 255) }
        let key = Data(bytes).base64EncodedString()
        defaults.set(key, forKey: deviceKeyKey)
        return key
    }

    func save(token: String, email: String) {
        self.token = token
        self.email = email
        defaults.set(token, forKey: tokenKey)
        defaults.set(email, forKey: emailKey)
    }

    func setDeviceType(_ type: String) {
        deviceType = type
        defaults.set(type, forKey: deviceTypeKey)
    }

    func setDeviceId(_ id: String) {
        deviceId = id
        defaults.set(id, forKey: deviceIdKey)
    }

    /// Signs out. Keeps `deviceKey` (identifies the physical device) but drops the
    /// per-account server device id, which is re-established on the next login.
    func clear() {
        token = nil
        email = nil
        deviceType = nil
        deviceId = nil
        defaults.removeObject(forKey: tokenKey)
        defaults.removeObject(forKey: emailKey)
        defaults.removeObject(forKey: deviceTypeKey)
        defaults.removeObject(forKey: deviceIdKey)
    }
}
