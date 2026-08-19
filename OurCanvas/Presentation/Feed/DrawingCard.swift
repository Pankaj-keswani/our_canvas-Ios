import SwiftUI

struct DrawingCard: View {
    let drawing: Drawing
    var onFavorite: () -> Void
    var onReact: (String) -> Void
    
    @State private var showingReactions = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 36, height: 36)
                    .overlay(Text(String(drawing.senderId.prefix(1).uppercased())).foregroundColor(.gray))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(drawing.senderId == FirebaseAuth.Auth.auth().currentUser?.uid ? "You" : "Friend")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    if let date = drawing.sentAt?.dateValue() {
                        Text(date, style: .relative)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                
                Button(action: onFavorite) {
                    Image(systemName: drawing.isFavorite ? "heart.fill" : "heart")
                        .foregroundColor(drawing.isFavorite ? .pink : .gray)
                }
            }
            .padding(16)
            
            // Image
            if let data = Data(base64Encoded: drawing.drawingData), let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .background(Color.white)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .aspectRatio(1, contentMode: .fit)
            }
            
            // Reactions Footer
            VStack(alignment: .leading, spacing: 12) {
                if !drawing.reactions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(drawing.reactions.keys.sorted()), id: \.self) { key in
                                if let reactionInfo = drawing.reactions[key] {
                                    HStack(spacing: 4) {
                                        Text(reactionInfo.emoji)
                                        Text(reactionInfo.senderName)
                                            .font(.caption2)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(12)
                                }
                            }
                        }
                    }
                }
                
                Button(action: { showingReactions.toggle() }) {
                    HStack {
                        Image(systemName: "face.smiling")
                        Text("React")
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                .popover(isPresented: $showingReactions) {
                    HStack(spacing: 16) {
                        ForEach(["❤️", "🔥", "😂", "😮", "😢"], id: \.self) { emoji in
                            Button(emoji) {
                                onReact(emoji)
                                showingReactions = false
                            }
                            .font(.title)
                        }
                    }
                    .padding()
                }
                
                Spacer()
                
                Button(action: { /* Replay Animation */ }) {
                    Image(systemName: "play.circle")
                        .foregroundColor(.gray)
                        .font(.title3)
                }
            }
            .padding(16)
        }
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
    }
}
