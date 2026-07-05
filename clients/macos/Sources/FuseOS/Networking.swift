import Foundation

enum Config {
    /// The FuseOS control-plane server. `pnpm --filter server dev` runs it on :3000.
    static let baseURL = URL(string: "http://localhost:3000")!
}

// MARK: - Wire models (see docs/api.md)

struct SignUpRequest: Encodable {
    let email: String
    let password: String
    let name: String?
}

struct SignInRequest: Encodable {
    let email: String
    let password: String
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
    var errorDescription: String? { message }
}

// MARK: - API client

struct AuthAPI {
    func signIn(email: String, password: String) async throws -> AuthResponse {
        try await post(path: "/auth/sign-in/email", body: SignInRequest(email: email, password: password))
    }

    func signUp(email: String, password: String, name: String?) async throws -> AuthResponse {
        try await post(path: "/auth/sign-up/email", body: SignUpRequest(email: email, password: password, name: name))
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
            throw AuthError(message: apiError.error.message)
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
    func signUp(email: String, password: String, name: String?) async throws {
        let result = try await api.signUp(email: email, password: password, name: name)
        SessionStore.shared.save(token: result.token, email: result.user.email)
    }
}
