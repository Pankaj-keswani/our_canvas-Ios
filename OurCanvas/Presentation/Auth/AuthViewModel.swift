import Foundation
import SwiftUI
import FirebaseAuth
import AuthenticationServices
import CryptoKit

/// Form-level state for the Auth screen. Session routing is owned by `AppRouter`,
/// which observes Firebase auth state independently — successful sign-ins here
/// advance the app through the router with no direct coupling.
@MainActor
class AuthViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var displayName = ""
    @Published var isSignUp = false
    @Published var isLoading = false
    @Published var errorText: String?

    // Sign in with Apple nonce (existing secure flow preserved).
    fileprivate var currentNonce: String?

    var canSubmit: Bool {
        email.trimmed.contains("@")
            && email.trimmed.contains(".")
            && password.count >= 6
            && (!isSignUp || !displayName.trimmed.isEmpty)
    }

    func toggleMode() {
        isSignUp.toggle()
        errorText = nil
    }

    func submit() {
        guard canSubmit else { return }
        let email = self.email.trimmed
        let password = self.password
        let name = displayName.trimmed

        isLoading = true
        errorText = nil
        Task {
            do {
                if isSignUp {
                    try await AuthService.signUp(email: email, password: password, displayName: name)
                } else {
                    try await AuthService.signIn(email: email, password: password)
                }
                self.isLoading = false
                // Router picks the new session up via the auth listener.
            } catch {
                self.isLoading = false
                self.errorText = AuthService.map(error).message
            }
        }
    }

    func signInWithGoogleTapped() {
        isLoading = true
        errorText = nil
        Task {
            do {
                try await AuthService.signInWithGoogle()
                self.isLoading = false
            } catch {
                self.isLoading = false
                self.errorText = AuthService.map(error).message
            }
        }
    }

    // MARK: - Sign in with Apple (nonce flow preserved from the original implementation)

    func startAppleSignIn(request: ASAuthorizationAppleIDRequest) {
        let nonce = randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
    }

    func completeAppleSignIn(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authResults):
            switch authResults.credential {
            case let appleIDCredential as ASAuthorizationAppleIDCredential:
                guard let nonce = currentNonce else {
                    errorText = AppError.underlying("A login callback arrived without a matching login request.").message
                    return
                }
                guard let appleIDToken = appleIDCredential.identityToken else {
                    errorText = AppError.underlying("Unable to fetch the Apple identity token.").message
                    return
                }
                guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                    errorText = AppError.underlying("Unable to serialize the Apple identity token.").message
                    return
                }

                let credential = OAuthProvider.appleCredential(
                    withIDToken: idTokenString,
                    rawNonce: nonce,
                    fullName: appleIDCredential.fullName
                )

                isLoading = true
                Auth.auth().signIn(with: credential) { [weak self] _, error in
                    Task { @MainActor in
                        guard let self else { return }
                        self.isLoading = false
                        if let error {
                            self.errorText = AuthService.map(error).message
                        }
                        // Success → the router's auth listener drives navigation.
                    }
                }
            default:
                break
            }
        case .failure(let error):
            errorText = AuthService.map(error).message
        }
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        return SHA256.hash(data: inputData).compactMap {
            String(format: "%02x", $0)
        }.joined()
    }
}
