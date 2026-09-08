import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Combine

class GroupsViewModel: ObservableObject {
    @Published var groups: [Group] = []
    @Published var isLoading = false
    @Published var inviteCode = ""
    @Published var newGroupName = ""
    @Published var errorText: String?

    private let groupRepo = GroupRepository()
    private let db = Firestore.firestore()

    init() {
        groupRepo.$groups
            .receive(on: RunLoop.main)
            .assign(to: &$groups)
        groupRepo.listenToUserGroups()
    }

    func createGroup() {
        let name = newGroupName.trimmed
        guard let uid = Auth.auth().currentUser?.uid, !name.isEmpty else { return }

        // Free plan: max 2 active circles (Android A7.3).
        let isPro = UserRepository.shared.currentUserProfile?.isPro ?? false
        if !PremiumGate.canCreateGroup(currentCount: groups.count, isPro: isPro) {
            errorText = "Free plan covers 2 circles. Upgrade to Pro for unlimited circles!"
            return
        }

        let newDoc = db.collection("groups").document()
        let code = String((0..<6).map { _ in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".randomElement()! })
        let fields = Group.creationFields(
            groupName: name,
            createdBy: uid,
            inviteCode: code,
            memberIds: [uid],
            createdAtMs: Int64(Date().timeIntervalSince1970 * 1000)
        )

        isLoading = true
        Task {
            do {
                try await newDoc.setData(fields)
                DispatchQueue.main.async {
                    self.newGroupName = ""
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorText = AppError.from(error).message
                }
            }
        }
    }

    func joinGroup() {
        let code = inviteCode.trimmed.uppercased()
        guard let uid = Auth.auth().currentUser?.uid, !code.isEmpty else { return }

        isLoading = true
        Task {
            do {
                let snapshot = try await db.collection("groups")
                    .whereField("inviteCode", isEqualTo: code)
                    .getDocuments()
                guard let doc = snapshot.documents.first else {
                    DispatchQueue.main.async {
                        self.inviteCode = ""
                        self.isLoading = false
                        self.errorText = "No circle found with that invite code. Double-check it and try again."
                    }
                    return
                }
                // Deployed rules: members may touch ONLY memberIds (+updatedAt).
                try await doc.reference.updateData([
                    "memberIds": FieldValue.arrayUnion([uid]),
                    "updatedAt": FieldValue.serverTimestamp(),
                ])
                DispatchQueue.main.async {
                    self.inviteCode = ""
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorText = AppError.from(error).message
                }
            }
        }
    }
}

struct GroupsView: View {
    @StateObject private var viewModel = GroupsViewModel()
    @State private var showingCreate = false
    @State private var showingJoin = false

    var body: some View {
        ZStack {
            Color(red: 247/255, green: 249/255, blue: 251/255).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    HStack(spacing: 16) {
                        Button(action: { showingCreate = true }) {
                            VStack {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title)
                                Text("Create Circle")
                                    .font(.subheadline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white)
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.05), radius: 5)
                        }

                        Button(action: { showingJoin = true }) {
                            VStack {
                                Image(systemName: "person.badge.plus")
                                    .font(.title)
                                Text("Join Circle")
                                    .font(.subheadline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white)
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.05), radius: 5)
                        }
                    }
                    .padding(.horizontal)

                    if viewModel.groups.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "person.3.sequence.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.gray.opacity(0.3))
                            Text("No Circles Yet")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("Create or join a circle to start drawing with friends.")
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.gray)
                                .padding(.horizontal)
                        }
                        .padding(.top, 60)
                    } else {
                        LazyVStack(spacing: 16) {
                            ForEach(viewModel.groups) { group in
                                NavigationLink(destination: FeedView(group: group)) {
                                    GroupCard(group: group)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
        }
        .navigationTitle("Circles")
        .alert("Something went wrong", isPresented: Binding(
            get: { viewModel.errorText != nil },
            set: { if !$0 { viewModel.errorText = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorText ?? "")
        }
        .alert("Create Circle", isPresented: $showingCreate) {
            TextField("Circle Name", text: $viewModel.newGroupName)
            Button("Cancel", role: .cancel) { }
            Button("Create") { viewModel.createGroup() }
        }
        .alert("Join Circle", isPresented: $showingJoin) {
            TextField("Invite Code", text: $viewModel.inviteCode)
                .autocapitalization(.allCharacters)
            Button("Cancel", role: .cancel) { }
            Button("Join") { viewModel.joinGroup() }
        }
    }
}
