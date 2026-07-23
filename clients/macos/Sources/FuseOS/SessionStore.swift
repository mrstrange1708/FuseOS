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

    private init() {
        token = defaults.string(forKey: tokenKey)
        email = defaults.string(forKey: emailKey)
        deviceType = defaults.string(forKey: deviceTypeKey)
        deviceId = defaults.string(forKey: deviceIdKey)
    }

    /// This device's public key as base64 SPKI DER — the `publicKey` the API expects.
    /// The keypair itself lives in the Keychain; see `DeviceKey`.
    var deviceKey: String {
        get throws { try DeviceKey.publicKeyBase64() }
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

    /// Signs out. Keeps the Keychain keypair (it identifies the physical device) but
    /// drops the per-account server device id, re-established on the next login.
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
