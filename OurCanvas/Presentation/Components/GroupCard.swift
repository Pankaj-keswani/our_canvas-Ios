import SwiftUI
import FirebaseFirestore

struct GroupCard: View {
    let group: Group
    @State private var latestDrawing: Drawing?
    @State private var isLoadingLatest = true
    
    var body: some View {
        HStack(spacing: 16) {
            // Group Avatar or Latest Drawing Preview
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 60, height: 60)
                
                if let drawing = latestDrawing, let data = Data(base64Encoded: drawing.drawingData), let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(Circle())
                } else if isLoadingLatest {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Image(systemName: "paintpalette.fill")
                        .foregroundColor(.pink.opacity(0.6))
                        .font(.title2)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(group.groupName)
                    .font(.headline)
                    .lineLimit(1)
                
                HStack {
                    Image(systemName: "person.2.fill")
                        .font(.caption2)
                    Text("\(group.memberIds.count) members")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.gray.opacity(0.5))
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        .onAppear {
            fetchLatestDrawing()
        }
    }
    
    private func fetchLatestDrawing() {
        Task {
            let repo = DrawingRepository()
            do {
                if let drawing = try await repo.getLatestDrawing(groupId: group.groupId) {
                    DispatchQueue.main.async {
                        self.latestDrawing = drawing
                        self.isLoadingLatest = false
                    }
                } else {
                    DispatchQueue.main.async {
                        self.isLoadingLatest = false
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoadingLatest = false
                }
            }
        }
    }
}
