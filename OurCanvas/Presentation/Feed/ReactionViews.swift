import SwiftUI
import FirebaseAuth

// MARK: - User avatar view

struct UserAvatarView: View {
    let uid: String
    var profileUrl: String = ""
    var profilePictureBase64: String = ""
    var size: CGFloat = 36

    var body: some View {
        SwiftUI.Group {
            if !profilePictureBase64.isEmpty,
               let data = Data(base64Encoded: profilePictureBase64),
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if !profileUrl.isEmpty, let url = URL(string: profileUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        fallbackAvatar
                    }
                }
            } else if let url = AvatarIdentity.url(forUid: uid) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        fallbackAvatar
                    }
                }
            } else {
                fallbackAvatar
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 1))
    }

    private var fallbackAvatar: some View {
        Circle()
            .fill(Color.gray.opacity(0.25))
            .overlay(
                Text(String(uid.prefix(1).uppercased()))
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundColor(.secondary)
            )
    }
}

// MARK: - Reaction chip (with Avatar + Emoji + Username pill)

struct ReactionChip: View {
    let reaction: ReactionInfo
    let user: User?
    var onTap: () -> Void

    private var currentUID: String? { Auth.auth().currentUser?.uid }

    private var displayName: String {
        if reaction.senderId == currentUID {
            return "You"
        }
        if let user, !user.displayName.isEmpty {
            return user.displayName.components(separatedBy: " ").first ?? user.displayName
        }
        if !reaction.senderName.isEmpty {
            return reaction.senderName.components(separatedBy: " ").first ?? reaction.senderName
        }
        return "Member"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                UserAvatarView(
                    uid: reaction.senderId,
                    profileUrl: reaction.profileUrl,
                    profilePictureBase64: user?.profilePictureBase64 ?? "",
                    size: 18
                )

                Text(reaction.emoji)
                    .font(.caption)

                Text(displayName)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.systemGray6))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Reactions detail bottom sheet

struct ReactionsDetailSheet: View {
    let drawing: Drawing
    var users: [String: User] = [:]

    @Environment(\.dismiss) private var dismiss
    @State private var resolvedUsers: [String: User] = [:]
    @State private var isLoading = true

    private var currentUID: String? { Auth.auth().currentUser?.uid }

    private var reactionsList: [ReactionInfo] {
        Array(drawing.reactions.values).sorted { ($0.reactedAt ?? .distantPast) > ($1.reactedAt ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            List {
                if reactionsList.isEmpty {
                    Text("No reactions yet.")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ForEach(reactionsList, id: \.senderId) { reaction in
                        let user = resolvedUsers[reaction.senderId] ?? users[reaction.senderId]
                        let isMe = reaction.senderId == currentUID
                        let name = isMe ? "You" : (user?.displayName.isEmpty == false ? user!.displayName : (reaction.senderName.isEmpty ? "Circle member" : reaction.senderName))
                        let isPro = user?.isPro ?? false

                        HStack(spacing: 12) {
                            UserAvatarView(
                                uid: reaction.senderId,
                                profileUrl: reaction.profileUrl,
                                profilePictureBase64: user?.profilePictureBase64 ?? "",
                                size: 42
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(name)
                                        .font(.subheadline.weight(.semibold))

                                    if isPro {
                                        Text("PRO")
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1.5)
                                            .background(
                                                LinearGradient(colors: [Color.pink, Color.purple],
                                                               startPoint: .leading, endPoint: .trailing)
                                            )
                                            .foregroundColor(.white)
                                            .clipShape(Capsule())
                                    }
                                }

                                if let date = reaction.reactedAt {
                                    Text(date, style: .relative)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            Text(reaction.emoji)
                                .font(.title2)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Reactions (\(drawing.reactions.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await loadUserProfiles()
            }
        }
    }

    private func loadUserProfiles() async {
        let uids = Array(drawing.reactions.keys)
        guard !uids.isEmpty else {
            isLoading = false
            return
        }
        let fetched = (try? await UserRepository.shared.getUsersBatch(uids: uids)) ?? [:]
        await MainActor.run {
            resolvedUsers = fetched
            isLoading = false
        }
    }
}
