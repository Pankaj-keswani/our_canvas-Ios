import Foundation
import UIKit
import FirebaseAuth
import GoogleSignIn

/// Authentication operations. The router observes Firebase auth state independently,
/// so none of these methods need to return session state — they only throw friendly errors.
enum AuthService {
    private static var googleConfigured = false

    private static func configureGoogleIfNeeded() throws {
        guard !googleConfigured else { return }
        guard let plistPath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plistDict = NSDictionary(contentsOfFile: plistPath),
              let clientID = plistDict["CLIENT_ID"] as? String else {
            throw AppError.underlying("Google Sign-In isn't configured for this build.")
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        googleConfigured = true
    }

    // MARK: - Email / password

    static func signIn(email: String, password: String) async throws {
        _ = try await Auth.auth().signIn(withEmail: email, password: password)
    }

    static func signUp(email: String, password: String, displayName: String) async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        if !displayName.isEmpty {
            let changeRequest = result.user.createProfileChangeRequest()
            changeRequest.displayName = displayName
            try await changeRequest.commitChanges()
        }
        try await result.user.sendEmailVerification()
    }

    static func resendVerificationEmail() async throws {
        guard let user = Auth.auth().currentUser else {
            throw AppError.underlying("You're not signed in.")
        }
        try await user.sendEmailVerification()
    }

    static func reloadCurrentUser() async throws {
        guard let user = Auth.auth().currentUser else { return }
        try await user.reload()
    }

    // MARK: - Google Sign-In

    static func signInWithGoogle() async throws {
        try configureGoogleIfNeeded()
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
              let rootViewController = scene.keyWindow?.rootViewController else {
            throw AppError.underlying("Couldn't present Google Sign-In. Please try again.")
        }

        let gidResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
        guard let idToken = gidResult.user.idToken?.tokenString else {
            throw AppError.underlying("Google Sign-In didn't return a token. Please try again.")
        }
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: gidResult.user.accessToken.tokenString
        )
        _ = try await Auth.auth().signIn(with: credential)
    }

    // MARK: - Session

    static func signOut() throws {
        try Auth.auth().signOut()
    }

    // MARK: - Friendly error mapping

    static func map(_ error: Error) -> AppError {
        let ns = error as NSError
        if ns.domain == "FIRAuthErrorDomain", let code = AuthErrorCode(rawValue: ns.code) {
            switch code {
            case .invalidEmail:
                return .invalidEmail
            case .emailAlreadyInUse, .credentialAlreadyInUse:
                return .emailAlreadyInUse
            case .weakPassword:
                return .weakPassword
            case .wrongPassword, .invalidCredential, .userCredentialMismatch:
                return .wrongCredentials
            case .userNotFound:
                return .userNotFound
            case .tooManyRequests:
                return .tooManyRequests
            case .networkError, .internalError:
                return .network
            case .userDisabled:
                return .underlying("This account has been disabled. Contact support if you believe this is a mistake.")
            default:
                break
            }
        }
        return AppError.from(error)
    }
}
