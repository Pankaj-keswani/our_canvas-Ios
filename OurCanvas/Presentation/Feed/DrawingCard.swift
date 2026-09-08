import SwiftUI
import FirebaseAuth
import UIKit

struct DrawingCard: View {
    let drawing: Drawing
    var senderName: String?
    var onFavorite: () -> Void
    var onReact: (String, String) -> Void
    var onReplay: () -> Void

    @State private var showingReactionPalette = false
    @State private var customReaction = ""
    @State private var saveMessage: String?

    private var gate: PremiumGate {
        PremiumGate(isPro: UserRepository.shared.currentUserProfile?.isPro ?? false)
    }

    private static let standardReactions: [(emoji: String, name: String)] = [
        ("❤️", "heart"), ("😂", "joy"), ("😮", "wow"), ("😢", "cry"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(16)

            image
                .onLongPressGesture {
                    showingReactionPalette = true
                }

            footer
                .padding(16)
        }
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
        .overlay(alignment: .center) {
            if showingReactionPalette {
                reactionPalette
            }
        }
        .alert(item: bindingSaveMessage) { message in
            Alert(title: Text(message.text), dismissButton: .default(Text("OK")))
        }
    }

    private var bindingSaveMessage: Binding<SaveMessage?> {
        Binding(get: { saveMessage.map { SaveMessage(text: $0) } },
                set: { saveMessage = $0?.text })
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            MemberAvatar(uid: drawing.senderId, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(displaySenderName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                if let date = drawing.sentAt {
                    Text(date, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()

            Menu {
                Button(action: onReplay) {
                    Label("Replay doodle", systemImage: "play.circle")
                }
                Button(action: share) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                Button(action: saveToPhotos) {
                    Label(gate.canSaveToDevice ? "Save to Photos" : "Save to Photos (Pro)",
                          systemImage: gate.canSaveToDevice ? "square.and.arrow.down" : "lock")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.gray)
            }

            Button(action: onFavorite) {
                Image(systemName: drawing.isFavorite ? "heart.fill" : "heart")
                    .foregroundColor(drawing.isFavorite ? .pink : .gray)
            }
        }
    }

    private var displaySenderName: String {
        if drawing.senderId == Auth.auth().currentUser?.uid {
            return "You"
        }
        if let senderName, !senderName.isEmpty {
            return senderName
        }
        return "Circle member"
    }

    // MARK: - Image

    @ViewBuilder
    private var image: some View {
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
    }

    // MARK: - Footer (reactions)

    private var footer: some View {
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

            HStack {
                Button(action: { showingReactionPalette = true }) {
                    HStack {
                        Image(systemName: "face.smiling")
                        Text("React")
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: onReplay) {
                    Image(systemName: "play.circle")
                        .foregroundColor(.gray)
                        .font(.title3)
                }
                .accessibilityLabel("Replay doodle")
            }
        }
    }

    // MARK: - Reaction palette (long-press, Android A4.4)

    private var reactionPalette: some View {
        VStack(spacing: 10) {
            HStack(spacing: 16) {
                ForEach(Self.standardReactions, id: \.emoji) { reaction in
                    Button {
                        onReact(reaction.emoji, reaction.name)
                        showingReactionPalette = false
                    } label: {
                        Text(reaction.emoji)
                            .font(.title)
                    }
                }
                Button {
                    onReact(customReaction.isEmpty ? "👍" : customReaction,
                            customReaction.isEmpty ? "thumbs_up" : customReaction)
                    customReaction = ""
                    showingReactionPalette = false
                } label: {
                    Text(customReaction.isEmpty ? "➕" : customReaction)
                        .font(.title2)
                        .frame(width: 40, height: 40)
                        .background(Circle().strokeBorder(Color.gray.opacity(0.4), lineWidth: 1))
                }
            }
            TextField("Custom reaction…", text: $customReaction)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
            Button("Cancel") {
                customReaction = ""
                showingReactionPalette = false
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 4)
        .padding(.horizontal, 24)
    }

    // MARK: - Export actions

    private func decodedImage() -> UIImage? {
        guard let data = Data(base64Encoded: drawing.drawingData) else { return nil }
        return UIImage(data: data)
    }

    private func share() {
        // Opens the system share sheet through the menu; uses the decoded bitmap.
        if let image = decodedImage() {
            let activityVC = UIActivityViewController(activityItems: [image], applicationActivities: nil)
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let root = scenes.first(where: { $0.activationState == .foregroundActive })?.keyWindow?.rootViewController {
                activityVC.popoverPresentationController?.sourceView = root.view
                root.present(activityVC, animated: true)
            }
        }
    }

    private func saveToPhotos() {
        guard gate.canSaveToDevice else {
            saveMessage = "Saving doodles to your device is a Pro feature."
            return
        }
        guard let image = decodedImage() else {
            saveMessage = "Couldn't load this doodle."
            return
        }
        PhotoLibrarySaver.save(image: image) { message in
            saveMessage = message
        }
    }
}

struct SaveMessage: Identifiable {
    let text: String
    var id: String { text }
}
