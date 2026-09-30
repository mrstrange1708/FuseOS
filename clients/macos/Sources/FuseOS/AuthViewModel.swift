import Foundation
import FuseOSCore

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
    /// A good-news line under the form, e.g. after asking for a reset link.
    @Published var notice: String?
    @Published var emailError: String?
    @Published var passwordError: String?
    @Published var nameError: String?

    private let repository = AuthRepository.shared
    /// Held while Google's sheet is up: the web session lives only as long as its owner.
    private var google: GoogleSignIn?

    func switchTo(_ newMode: Mode) {
        mode = newMode
        error = nil
        notice = nil
        emailError = nil
        passwordError = nil
        nameError = nil
    }

    func submit() {
        let trimmedEmail = email.trimmed
        let trimmedName = name.trimmed
        emailError = Self.isValidEmail(trimmedEmail) ? nil : "Enter a valid email address"
        passwordError = password.count >= 8 ? nil : "Use at least 8 characters"
        // Name is required when creating an account.
        nameError = (mode == .signUp && trimmedName.isEmpty) ? "Enter your name" : nil
        guard emailError == nil, passwordError == nil, nameError == nil else { return }

        error = nil
        isSubmitting = true
        Task {
            do {
                if mode == .signIn {
                    try await repository.signIn(email: trimmedEmail, password: password)
                } else {
                    try await repository.signUp(email: trimmedEmail, password: password, name: trimmedName)
                }
                // On success, SessionStore updates and the app swaps to Home.
            } catch {
                self.error = (error as? AuthError)?.message ?? error.localizedDescription
            }
            isSubmitting = false
        }
    }

    /// "Forgot password?": a reset link to the email typed above.
    func forgotPassword() {
        let trimmedEmail = email.trimmed
        guard Self.isValidEmail(trimmedEmail) else {
            emailError = "Enter your email above, then tap Forgot password"
            return
        }
        error = nil
        notice = nil
        isSubmitting = true
        Task {
            do {
                try await AuthAPI().requestPasswordReset(email: trimmedEmail)
                notice = "If there's an account for \(trimmedEmail), a reset link is on its way. Check your inbox."
            } catch {
                self.error = (error as? AuthError)?.message ?? error.localizedDescription
            }
            isSubmitting = false
        }
    }

    func continueWithGoogle() {
        guard !isSubmitting else { return }
        error = nil
        isSubmitting = true
        let google = GoogleSignIn()
        self.google = google
        Task {
            do {
                // nil: the sheet was closed — nothing to say.
                if let idToken = try await google.idToken() {
                    try await repository.signInWithGoogle(idToken: idToken)
                }
            } catch {
                self.error = (error as? AuthError)?.message ?? error.localizedDescription
            }
            self.google = nil
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
