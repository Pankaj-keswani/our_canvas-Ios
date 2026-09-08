import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @StateObject private var viewModel = AuthViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 48)

                Image(systemName: "paintpalette.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .foregroundStyle(BrandGradient.primary)

                VStack(spacing: 6) {
                    Text("Our Canvas")
                        .font(BrandFont.title())
                        .foregroundColor(BrandColor.textPrimary)
                    Text("Draw together, wherever you are.")
                        .font(BrandFont.body())
                        .foregroundColor(BrandColor.textSecondary)
                }

                // Email / password
                VStack(spacing: 12) {
                    if viewModel.isSignUp {
                        TextField("Your name", text: $viewModel.displayName)
                            .textContentType(.name)
                            .fieldStyle()
                    }

                    TextField("Email", text: $viewModel.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .fieldStyle()

                    SecureField("Password (6+ characters)", text: $viewModel.password)
                        .textContentType(.password)
                        .fieldStyle()

                    if let error = viewModel.errorText {
                        Text(error)
                            .font(BrandFont.caption())
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    PrimaryGradientButton(
                        title: viewModel.isSignUp ? "Create Account" : "Sign In",
                        isLoading: viewModel.isLoading
                    ) {
                        viewModel.submit()
                    }
                    .opacity(viewModel.canSubmit ? 1.0 : 0.5)
                    .disabled(!viewModel.canSubmit)

                    Button(viewModel.isSignUp ? "Already have an account? Sign In"
                                              : "New here? Create an Account") {
                        viewModel.toggleMode()
                    }
                    .font(BrandFont.caption())
                    .foregroundColor(BrandColor.primary)
                }
                .glassCard()

                // Social providers
                VStack(spacing: 12) {
                    Text("or continue with")
                        .font(BrandFont.caption())
                        .foregroundColor(BrandColor.textSecondary)

                    SignInWithAppleButton(.signIn) { request in
                        viewModel.startAppleSignIn(request: request)
                    } onCompletion: { result in
                        viewModel.completeAppleSignIn(result: result)
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 50)
                    .cornerRadius(12)

                    Button(action: { viewModel.signInWithGoogleTapped() }) {
                        Text("Continue with Google")
                            .font(BrandFont.headline())
                            .foregroundColor(BrandColor.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(BrandColor.surface.opacity(0.7))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                            )
                            .cornerRadius(12)
                    }
                    .disabled(viewModel.isLoading)
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 32)
            }
            .padding(.horizontal, 20)
        }
        .background(BrandBackground())
    }
}

private extension View {
    func fieldStyle() -> some View {
        self
            .padding(14)
            .background(BrandColor.surface.opacity(0.7))
            .cornerRadius(12)
            .foregroundStyle(BrandColor.textPrimary)
            .autocorrectionDisabled()
    }
}

struct AuthView_Previews: PreviewProvider {
    static var previews: some View {
        AuthView()
    }
}
