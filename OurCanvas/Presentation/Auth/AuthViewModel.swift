import Foundation
import FirebaseAuth
import AuthenticationServices
import CryptoKit

class AuthViewModel: ObservableObject {
    @Published var userSession: FirebaseAuth.User?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // For Apple Sign In
    fileprivate var currentNonce: String?
    
    init() {
        self.userSession = Auth.auth().currentUser
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.userSession = user
        }
    }
    
    func signOut() {
        do {
            try Auth.auth().signOut()
        } catch {
            self.errorMessage = "Failed to sign out: \(error.localizedDescription)"
        }
    }
    
    // Helper function for Apple Sign In nonce
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let nonce = randomBytes.map { byte in
            charset[Int(byte) % charset.count]
        }
        return String(nonce)
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        return hashString
    }
    
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
                    fatalError("Invalid state: A login callback was received, but no login request was sent.")
                }
                guard let appleIDToken = appleIDCredential.identityToken else {
                    self.errorMessage = "Unable to fetch identity token"
                    return
                }
                guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                    self.errorMessage = "Unable to serialize token string from data: \(appleIDToken.debugDescription)"
                    return
                }
                
                let credential = OAuthProvider.appleCredential(withIDToken: idTokenString,
                                                             rawNonce: nonce,
                                                             fullName: appleIDCredential.fullName)
                
                self.isLoading = true
                Auth.auth().signIn(with: credential) { [weak self] authResult, error in
                    DispatchQueue.main.async {
                        self?.isLoading = false
                        if let error = error {
                            self?.errorMessage = error.localizedDescription
                            return
                        }
                        self?.handleSuccessfulLogin(user: authResult?.user, fullName: appleIDCredential.fullName)
                    }
                }
            default:
                break
            }
        case .failure(let error):
            self.errorMessage = error.localizedDescription
        }
    }
    
    private func handleSuccessfulLogin(user: FirebaseAuth.User?, fullName: PersonNameComponents?) {
        guard let user = user else { return }
        Task {
            do {
                let userRepo = UserRepository.shared
                if try await userRepo.getUser(uid: user.uid) == nil {
                    // Create new user profile in Firestore
                    let name = [fullName?.givenName, fullName?.familyName].compactMap { $0 }.joined(separator: " ")
                    let newUser = User(
                        uid: user.uid,
                        displayName: name.isEmpty ? (user.displayName ?? "") : name,
                        email: user.email ?? "",
                        plan: "free"
                    )
                    try await userRepo.updateUser(newUser)
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to sync profile: \(error.localizedDescription)"
                }
            }
        }
    }
}
