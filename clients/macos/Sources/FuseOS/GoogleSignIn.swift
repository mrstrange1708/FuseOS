import AppKit
import AuthenticationServices
import CryptoKit
import Foundation

/// Sign in with Google on the Mac: Google's own page in the system's web sheet, then the
/// authorization code swapped for an ID token, which `/auth/google` verifies (docs/api.md).
///
/// The client is an iOS-type one (project fuseos-510109) — the kind Google lets a native
/// app use with a custom-scheme redirect and PKCE instead of a secret, so nothing secret
/// ships in the app. Its id is public; the server accepts it as an audience.
@MainActor
final class GoogleSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let clientID = "988990113872-lmb0vpom5jcun4dgit9ne8itiokusk64.apps.googleusercontent.com"
    /// The client id reversed: Google redirects to it, and only this app's session hears it.
    private static let scheme = "com.googleusercontent.apps.988990113872-lmb0vpom5jcun4dgit9ne8itiokusk64"
    private static let redirect = scheme + ":/oauth2redirect"

    private var session: ASWebAuthenticationSession?

    /// The ID token, or nil when the person closed the sheet.
    func idToken() async throws -> String? {
        let verifier = Self.randomURLSafe(32)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        let state = Self.randomURLSafe(16)
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        guard let callback = try await present(components.url!) else { return nil }

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }
        if value("error") == "access_denied" { return nil }
        guard value("state") == state, let code = value("code") else {
            throw AuthError(message: "Google sign-in didn't finish. Try again.")
        }
        return try await exchange(code: code, verifier: verifier)
    }

    /// Shows Google's page; resolves with the redirect, or nil if the sheet was closed.
    private func present(_ url: URL) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            // Resumed exactly once, whichever of the handler or a failed start comes first.
            var resumed = false
            let finish = { (result: Result<URL?, Error>) in
                guard !resumed else { return }
                resumed = true
                continuation.resume(with: result)
            }
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: Self.scheme) { url, error in
                Task { @MainActor in
                    if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                        finish(.success(nil))
                    } else if let error {
                        finish(.failure(error))
                    } else {
                        finish(.success(url))
                    }
                }
            }
            session.presentationContextProvider = self
            self.session = session
            if !session.start() {
                finish(.failure(AuthError(message: "Couldn't open Google sign-in.")))
            }
        }
    }

    private func exchange(code: String, verifier: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: verifier),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirect),
        ]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        struct Tokens: Decodable { let id_token: String }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let tokens = try? JSONDecoder().decode(Tokens.self, from: data)
        else { throw AuthError(message: "Google sign-in didn't finish. Try again.") }
        return tokens.id_token
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor() }
    }

    private static func randomURLSafe(_ bytes: Int) -> String {
        var data = Data(count: bytes)
        _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
        return data.base64URLEncoded
    }
}

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
