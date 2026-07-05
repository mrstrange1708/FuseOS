import Foundation

/// Persists the signed-in session (token + email).
///
/// Dev note: for production, the token belongs in the Keychain, not UserDefaults.
@MainActor
final class SessionStore: ObservableObject {
    static let shared = SessionStore()

    @Published private(set) var token: String?
    @Published private(set) var email: String?

    private let defaults = UserDefaults.standard
    private let tokenKey = "fuse.token"
    private let emailKey = "fuse.email"

    private init() {
        token = defaults.string(forKey: tokenKey)
        email = defaults.string(forKey: emailKey)
    }

    func save(token: String, email: String) {
        self.token = token
        self.email = email
        defaults.set(token, forKey: tokenKey)
        defaults.set(email, forKey: emailKey)
    }

    func clear() {
        token = nil
        email = nil
        defaults.removeObject(forKey: tokenKey)
        defaults.removeObject(forKey: emailKey)
    }
}
