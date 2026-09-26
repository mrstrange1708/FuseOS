import Foundation
import FuseOSCore

/// Persists the signed-in session (token + email), the name the user gave this device,
/// and this install's stable device identity (key + server device id).
///
/// Dev note: for production, the token belongs in the Keychain, not UserDefaults.
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
        token = defaults.string(forKey: tokenKey)
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
        defaults.set(token, forKey: tokenKey)
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
        defaults.removeObject(forKey: tokenKey)
    }

    /// Signs out. Keeps the Keychain keypair (it identifies the physical device) but
    /// drops the per-account server device id, re-established on the next login.
    func clear() {
        token = nil
        email = nil
        deviceName = nil
        deviceId = nil
        defaults.removeObject(forKey: tokenKey)
        defaults.removeObject(forKey: emailKey)
        defaults.removeObject(forKey: deviceNameKey)
        defaults.removeObject(forKey: deviceIdKey)
    }
}
