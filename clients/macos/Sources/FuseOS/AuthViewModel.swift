import Foundation

@MainActor
final class AuthViewModel: ObservableObject {
    enum Mode {
        case signIn
        case signUp
    }

    @Published var mode: Mode = .signIn
    @Published var email = ""
    @Published var password = ""
    @Published var name = ""
    @Published var isSubmitting = false
    @Published var error: String?
    @Published var emailError: String?
    @Published var passwordError: String?

    private let repository = AuthRepository.shared

    func switchTo(_ newMode: Mode) {
        mode = newMode
        error = nil
        emailError = nil
        passwordError = nil
    }

    func submit() {
        let trimmedEmail = email.trimmed
        emailError = Self.isValidEmail(trimmedEmail) ? nil : "Enter a valid email address"
        passwordError = password.count >= 8 ? nil : "Use at least 8 characters"
        guard emailError == nil, passwordError == nil else { return }

        error = nil
        isSubmitting = true
        Task {
            do {
                if mode == .signIn {
                    try await repository.signIn(email: trimmedEmail, password: password)
                } else {
                    let trimmedName = name.trimmed
                    try await repository.signUp(
                        email: trimmedEmail,
                        password: password,
                        name: trimmedName.isEmpty ? nil : trimmedName,
                    )
                }
                // On success, SessionStore updates and the app swaps to Home.
            } catch {
                self.error = (error as? AuthError)?.message ?? error.localizedDescription
            }
            isSubmitting = false
        }
    }

    private static func isValidEmail(_ value: String) -> Bool {
        let pattern = "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        return value.range(of: pattern, options: .regularExpression) != nil
    }
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
