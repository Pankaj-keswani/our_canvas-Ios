import Foundation

/// Central, user-safe error abstraction for the app.
/// Later phases extend this with drawing limits, purchases, permissions, etc.
enum AppError: Error, Equatable {
    case network
    case invalidEmail
    case weakPassword
    case emailAlreadyInUse
    case wrongCredentials
    case userNotFound
    case tooManyRequests
    case emailNotVerified
    case invalidInput(String)
    case notFound(String)
    case permissionDenied
    case decodingFailed
    case drawingLimitReached
    case purchaseFailed
    case underlying(String)

    var title: String {
        switch self {
        case .network: return "Connection Problem"
        case .invalidEmail: return "Invalid Email"
        case .weakPassword: return "Weak Password"
        case .emailAlreadyInUse: return "Email Already in Use"
        case .wrongCredentials: return "Sign In Failed"
        case .userNotFound: return "Account Not Found"
        case .tooManyRequests: return "Too Many Attempts"
        case .emailNotVerified: return "Email Not Verified"
        case .invalidInput: return "Check Your Details"
        case .notFound: return "Not Found"
        case .permissionDenied: return "Permission Denied"
        case .decodingFailed: return "Data Problem"
        case .drawingLimitReached: return "Free Plan Limit Reached"
        case .purchaseFailed: return "Purchase Failed"
        case .underlying: return "Something Went Wrong"
        }
    }

    var message: String {
        switch self {
        case .network:
            return "We couldn't reach the server. Check your internet connection and try again."
        case .invalidEmail:
            return "That email address doesn't look right. Please double-check it."
        case .weakPassword:
            return "Passwords need at least 6 characters. Try a longer one."
        case .emailAlreadyInUse:
            return "An account already exists with this email. Try signing in instead."
        case .wrongCredentials:
            return "That email and password combination didn't match. Please try again."
        case .userNotFound:
            return "We couldn't find an account with those details."
        case .tooManyRequests:
            return "Too many attempts in a short time. Please wait a moment and try again."
        case .emailNotVerified:
            return "Please verify your email address before continuing."
        case .invalidInput(let detail):
            return detail
        case .notFound(let what):
            return "\(what) could not be found."
        case .permissionDenied:
            return "You don't have permission to do that."
        case .decodingFailed:
            return "Some data looked unexpected. Please try again."
        case .drawingLimitReached:
            return "You've reached the free plan limit of drawings for this circle. Upgrade to Pro to keep the doodles flowing."
        case .purchaseFailed:
            return "The purchase couldn't be completed. Please try again."
        case .underlying(let detail):
            return detail.isEmpty ? "Something went wrong. Please try again." : detail
        }
    }

    /// Maps arbitrary errors (network / firestore / unknown) to a friendly AppError.
    /// Firebase Auth errors are mapped in `AuthService.map(_:)` which can import FirebaseAuth.
    static func from(_ error: Error) -> AppError {
        // Already-typed errors (services, worker client) must keep their message —
        // bridging them through NSError would degrade to a generic bridging string.
        if let typed = error as? AppError { return typed }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return .network
        }
        if ns.domain == "FIRFirestoreErrorDomain" && ns.code == 14 {
            return .network
        }
        if ns.domain == "FIRFirestoreErrorDomain" && ns.code == 7 {
            return .permissionDenied
        }
        let detail = ns.localizedDescription
        return .underlying(detail)
    }
}
