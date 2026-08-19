import Foundation
import FirebaseFirestore
import FirebaseFirestoreSwift
import FirebaseAuth

class UserRepository: ObservableObject {
    private let db = Firestore.firestore()
    static let shared = UserRepository()
    
    @Published var currentUserProfile: User?
    private var memoryCache: [String: User] = [:]
    
    func getUser(uid: String) async throws -> User? {
        if let cached = memoryCache[uid] {
            return cached
        }
        
        let docRef = db.collection("users").document(uid)
        let snapshot = try await docRef.getDocument()
        guard let user = try? snapshot.data(as: User.self) else { return nil }
        
        let finalUser = mapTestUserPlan(user: user)
        memoryCache[uid] = finalUser
        
        if uid == Auth.auth().currentUser?.uid {
            DispatchQueue.main.async {
                self.currentUserProfile = finalUser
            }
        }
        
        return finalUser
    }
    
    func updateUser(_ user: User) async throws {
        var mutableUser = user
        if mutableUser.id == nil { mutableUser.id = user.uid }
        try db.collection("users").document(user.uid).setData(from: mutableUser)
        memoryCache[user.uid] = user
        
        if user.uid == Auth.auth().currentUser?.uid {
            DispatchQueue.main.async {
                self.currentUserProfile = user
            }
        }
    }
    
    func updateProfileFields(uid: String, updates: [String: Any]) async throws {
        try await db.collection("users").document(uid).updateData(updates)
        _ = try await getUser(uid: uid)
    }
    
    private func mapTestUserPlan(user: User) -> User {
        var modified = user
        let email = user.email.lowercased()
        let isTestUser = email.hasSuffix("@prempatra.com") || 
                         email.hasSuffix("@prempatra.test") ||
                         email.hasSuffix("@google.com")
        if isTestUser {
            modified.plan = "pro"
        }
        return modified
    }
    
    func getUsersBatch(uids: [String]) async throws -> [String: User] {
        if uids.isEmpty { return [:] }
        var results: [String: User] = [:]
        var uncachedUids: [String] = []
        
        for uid in uids {
            if let cached = memoryCache[uid] {
                results[uid] = cached
            } else {
                uncachedUids.append(uid)
            }
        }
        
        if uncachedUids.isEmpty { return results }
        
        let chunks = uncachedUids.chunked(into: 10)
        
        try await withThrowingTaskGroup(of: [User].self) { group in
            for chunk in chunks {
                group.addTask {
                    let snapshot = try await self.db.collection("users")
                        .whereField(FieldPath.documentID(), in: chunk)
                        .getDocuments()
                    return snapshot.documents.compactMap { try? $0.data(as: User.self) }
                }
            }
            
            for try await users in group {
                for user in users {
                    let finalUser = self.mapTestUserPlan(user: user)
                    self.memoryCache[user.uid] = finalUser
                    results[user.uid] = finalUser
                }
            }
        }
        return results
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
