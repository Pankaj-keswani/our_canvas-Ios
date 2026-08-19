import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
class FeedViewModel: ObservableObject {
    @Published var drawings: [Drawing] = []
    @Published var group: Group
    @Published var isLoading = true
    
    private let drawingRepo = DrawingRepository()
    private var listenerRegistration: ListenerRegistration?
    
    init(group: Group) {
        self.group = group
        listenToDrawings()
    }
    
    deinit {
        listenerRegistration?.remove()
    }
    
    func listenToDrawings() {
        isLoading = true
        listenerRegistration?.remove()
        
        listenerRegistration = drawingRepo.listenToDrawings(groupId: group.groupId) { [weak self] newDrawings in
            DispatchQueue.main.async {
                self?.drawings = newDrawings
                self?.isLoading = false
            }
        }
    }
    
    func toggleFavorite(drawing: Drawing) {
        let newStatus = !drawing.isFavorite
        guard let id = drawing.id else { return }
        Task {
            try? await drawingRepo.toggleFavorite(drawingId: id, isFavorite: newStatus)
        }
    }
    
    func addReaction(drawing: Drawing, emoji: String) {
        guard let id = drawing.id,
              let currentUser = Auth.auth().currentUser else { return }
        let userName = currentUser.displayName ?? "Someone"
        Task {
            try? await drawingRepo.addReaction(drawingId: id, emoji: emoji, senderName: userName, senderId: currentUser.uid)
        }
    }
}
