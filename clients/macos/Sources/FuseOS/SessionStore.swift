import Foundation
import Security
import FuseOSCore

/// Persists the signed-in session (token + email), the name the user gave this device,
/// and this install's stable device identity (key + server device id).
///
/// The token lives in the login Keychain; the rest is not secret and stays in defaults.
@MainActor
final class SessionStore: ObservableObject {
    static let shared = SessionStore()

    @Published private(set) var token: String?
    @Published private(set) var email: String?
    /// What the user called this Mac. Nil until they have been through naming, which is
    /// also what routes them there. Stored locally because `POST /devices` upserts the
    /// name on every launch — sending the detected name each time would overwrite
    /// whatever they chose.
    @Published private(set) var deviceName: String?
    @Published private(set) var deviceId: String?

    private let defaults = UserDefaults.standard
    private let tokenKey = "fuse.token"
    private let emailKey = "fuse.email"
    private let deviceNameKey = "fuse.deviceName"
    private let deviceIdKey = "fuse.deviceId"

    private init() {
        // Tokens used to live in defaults; move one across once, then forget it there.
        if let legacy = defaults.string(forKey: tokenKey) {
            TokenKeychain.write(legacy)
            defaults.removeObject(forKey: tokenKey)
        }
        token = TokenKeychain.read()
        email = defaults.string(forKey: emailKey)
        deviceName = defaults.string(forKey: deviceNameKey)
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
        TokenKeychain.write(token)
        defaults.set(email, forKey: emailKey)
    }

    func setDeviceName(_ name: String) {
        deviceName = name
        defaults.set(name, forKey: deviceNameKey)
    }

    /// What this Mac is called by default — the name the user already gave it in System
    /// Settings, which is the one they will recognise.
    static func detectedDeviceName() -> String {
        Host.current().localizedName ?? "Mac"
    }

    func setDeviceId(_ id: String) {
        deviceId = id
        defaults.set(id, forKey: deviceIdKey)
    }

    /// The server no longer accepts our token (it expired, or was revoked). Only the token
    /// goes: the device name and id still hold, so signing back in picks up where it was.
    func expire() {
        token = nil
        TokenKeychain.write(nil)
    }

    /// Signs out. Keeps the Keychain keypair (it identifies the physical device) but
    /// drops the per-account server device id, re-established on the next login.
    func clear() {
        token = nil
        email = nil
        deviceName = nil
        deviceId = nil
        TokenKeychain.write(nil)
        defaults.removeObject(forKey: emailKey)
        defaults.removeObject(forKey: deviceNameKey)
        defaults.removeObject(forKey: deviceIdKey)
    }
}

/// The session token in the login Keychain, where other apps and backups cannot read it
/// the way they can read preferences.
private enum TokenKeychain {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.fuseos.session",
        kSecAttrAccount as String: "token",
    ]

    static func read() -> String? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Replaces the stored token; nil removes it.
    static func write(_ token: String?) {
        SecItemDelete(query as CFDictionary)
        guard let token else { return }
        var add = query
        add[kSecValueData as String] = Data(token.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}
