import SwiftUI

struct AuthView: View {
    @StateObject private var viewModel = AuthViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                switch viewModel.mode {
                case .signIn:
                    LoginView(viewModel: viewModel)
                case .signUp:
                    SignUpView(viewModel: viewModel)
                }
            }
            .padding(32)
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FuseColor.bg)
    }
}

struct LoginView: View {
    @ObservedObject var viewModel: AuthViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark()
            Spacer().frame(height: 30)

            Text("Welcome back")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(FuseColor.ink)
            Text("Sign in to fuse your devices.")
                .font(.system(size: 14))
                .foregroundStyle(FuseColor.muted)
                .padding(.top, 6)

            Spacer().frame(height: 26)

            FuseTextField(title: "Email", text: $viewModel.email, error: viewModel.emailError)
            Spacer().frame(height: 12)
            FuseTextField(title: "Password", text: $viewModel.password, isSecure: true, error: viewModel.passwordError)
                .onSubmit { viewModel.submit() }

            if let error = viewModel.error {
                ErrorBanner(message: error).padding(.top, 14)
            }

            Spacer().frame(height: 22)
            PrimaryButton(title: "Sign in", loading: viewModel.isSubmitting) { viewModel.submit() }
            SwitchRow(prompt: "New to FuseOS?", action: "Create account") {
                viewModel.switchTo(.signUp)
            }
            .padding(.top, 12)
        }
    }
}

struct SignUpView: View {
    @ObservedObject var viewModel: AuthViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark()
            Spacer().frame(height: 30)

            Text("Create your account")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(FuseColor.ink)
            Text("One account fuses all your devices.")
                .font(.system(size: 14))
                .foregroundStyle(FuseColor.muted)
                .padding(.top, 6)

            Spacer().frame(height: 26)

            FuseTextField(title: "Your name", text: $viewModel.name, error: viewModel.nameError)
            Spacer().frame(height: 12)
            FuseTextField(title: "Email", text: $viewModel.email, error: viewModel.emailError)
            Spacer().frame(height: 12)
            FuseTextField(title: "Password (min 8 characters)", text: $viewModel.password, isSecure: true, error: viewModel.passwordError)
                .onSubmit { viewModel.submit() }

            if let error = viewModel.error {
                ErrorBanner(message: error).padding(.top, 14)
            }

            Spacer().frame(height: 22)
            PrimaryButton(title: "Create account", loading: viewModel.isSubmitting) { viewModel.submit() }
            SwitchRow(prompt: "Already have an account?", action: "Sign in") {
                viewModel.switchTo(.signIn)
            }
            .padding(.top, 12)
        }
    }
}
