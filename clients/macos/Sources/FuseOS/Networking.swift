import Foundation
import FuseOSCore

// MARK: - Wire models (see docs/api.md)

struct SignUpRequest: Encodable {
    let email: String
    let password: String
    let name: String
}

struct SignInRequest: Encodable {
    let email: String
    let password: String
}

struct PasswordResetRequest: Encodable {
    let email: String
}

struct GoogleSignInRequest: Encodable {
    let idToken: String
}

struct AuthUser: Decodable {
    let id: String
    let email: String
    let name: String?
}

struct AuthResponse: Decodable {
    let token: String
    let user: AuthUser
}

struct APIError: Decodable {
    struct Body: Decodable {
        let code: String
        let message: String
    }
    let error: Body
}

struct AuthError: LocalizedError {
    let message: String
    /// The API's machine-readable `error.code`, when the server sent one — some
    /// failures are recoverable and the caller has to tell which.
    var code: String? = nil
    var errorDescription: String? { message }
}

// MARK: - API client

struct AuthAPI {
    func signIn(email: String, password: String) async throws -> AuthResponse {
        try await post(path: "/auth/sign-in/email", body: SignInRequest(email: email, password: password))
    }

    /// Signs in, or up, with an ID token from `GoogleSignIn`.
    func signInWithGoogle(idToken: String) async throws -> AuthResponse {
        try await post(path: "/auth/google", body: GoogleSignInRequest(idToken: idToken))
    }

    func signUp(email: String, password: String, name: String) async throws -> AuthResponse {
        try await post(path: "/auth/sign-up/email", body: SignUpRequest(email: email, password: password, name: name))
    }

    /// Emails a reset link (a page on the server). The answer is the same whether or not the
    /// account exists, so there is nothing to decode on success.
    func requestPasswordReset(email: String) async throws {
        guard let url = URL(string: Config.baseURL.absoluteString + "/auth/request-password-reset") else {
            throw AuthError(message: "Invalid server URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(PasswordResetRequest(email: email))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            if let apiError = try? JSONDecoder().decode(APIError.self, from: data) {
                throw AuthError(message: apiError.error.message, code: apiError.error.code)
            }
            throw AuthError(message: "Couldn't reach the FuseOS server. Try again.")
        }
    }

    /// Ends this session on the server, so the token stops working everywhere at once.
    /// Best effort: signing out locally must not wait on, or fail with, the network.
    static func signOut(token: String) async {
        guard let url = URL(string: Config.baseURL.absoluteString + "/auth/sign-out") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 5
        _ = try? await URLSession.shared.data(for: request)
    }

    private func post<Body: Encodable>(path: String, body: Body) async throws -> AuthResponse {
        guard let url = URL(string: Config.baseURL.absoluteString + path) else {
            throw AuthError(message: "Invalid server URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError(message: "No response from the FuseOS server.")
        }
        if (200 ..< 300).contains(http.statusCode) {
            return try JSONDecoder().decode(AuthResponse.self, from: data)
        }
        if let apiError = try? JSONDecoder().decode(APIError.self, from: data) {
            throw AuthError(message: apiError.error.message, code: apiError.error.code)
        }
        throw AuthError(message: "Something went wrong (\(http.statusCode)). Is the FuseOS server running?")
    }
}

// MARK: - Repository

struct AuthRepository {
    static let shared = AuthRepository()
    private let api = AuthAPI()

    @MainActor
    func signIn(email: String, password: String) async throws {
        let result = try await api.signIn(email: email, password: password)
        SessionStore.shared.save(token: result.token, email: result.user.email)
    }

    @MainActor
    func signInWithGoogle(idToken: String) async throws {
        let result = try await api.signInWithGoogle(idToken: idToken)
        SessionStore.shared.save(token: result.token, email: result.user.email)
    }

    @MainActor
    func signUp(email: String, password: String, name: String) async throws {
        let result = try await api.signUp(email: email, password: password, name: name)
        SessionStore.shared.save(token: result.token, email: result.user.email)
    }
}
