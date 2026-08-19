import Foundation
import FirebaseAuth
import Combine

@MainActor
class HomeViewModel: ObservableObject {
    @Published var currentUserProfile: User?
    @Published var groups: [Group] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var cancellables = Set<AnyCancellable>()
    private let groupRepo = GroupRepository()
    
    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good Morning"
        case 12..<17: return "Good Afternoon"
        case 17..<22: return "Good Evening"
        default: return "Good Night"
        }
    }
    
    var userName: String {
        if let name = currentUserProfile?.displayName, !name.isEmpty {
            return name
        }
        if let authName = Auth.auth().currentUser?.displayName, !authName.isEmpty {
            return authName
        }
        return "Partner"
    }
    
    init() {
        groupRepo.$groups
            .receive(on: RunLoop.main)
            .assign(to: &$groups)
        
        UserRepository.shared.$currentUserProfile
            .receive(on: RunLoop.main)
            .assign(to: &$currentUserProfile)
            
        loadData()
    }
    
    func loadData() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        
        Task {
            do {
                _ = try await UserRepository.shared.getUser(uid: uid)
                groupRepo.listenToUserGroups()
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
    
    func refreshGroups() {
        groupRepo.listenToUserGroups()
    }
}
