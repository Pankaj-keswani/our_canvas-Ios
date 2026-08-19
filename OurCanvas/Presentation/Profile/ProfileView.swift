import SwiftUI
import FirebaseAuth

class ProfileViewModel: ObservableObject {
    @Published var currentUserProfile: User?
    @Published var premiumState: PremiumState = PremiumState()
    
    private let premiumManager = PremiumManager()
    
    init() {
        UserRepository.shared.$currentUserProfile.assign(to: &$currentUserProfile)
        premiumManager.$premiumState.assign(to: &$premiumState)
    }
    
    func logout() {
        do {
            try Auth.auth().signOut()
        } catch {
            print("Error signing out: \(error)")
        }
    }
}

struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()
    @EnvironmentObject var authViewModel: AuthViewModel
    
    var body: some View {
        ZStack {
            Color(red: 247/255, green: 249/255, blue: 251/255).ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        if let base64 = viewModel.currentUserProfile?.profilePictureBase64, !base64.isEmpty,
                           let data = Data(base64Encoded: base64), let image = UIImage(data: data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 100))
                                .foregroundColor(.gray.opacity(0.3))
                        }
                        
                        Text(viewModel.currentUserProfile?.displayName ?? "User")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        if viewModel.premiumState.isPremium {
                            Text("PRO MEMBER")
                                .font(.caption)
                                .fontWeight(.black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color.yellow)
                                .foregroundColor(.black)
                                .cornerRadius(8)
                        }
                    }
                    .padding(.top, 24)
                    
                    // Stats
                    HStack(spacing: 16) {
                        StatCard(title: "Current Streak", value: "\(viewModel.currentUserProfile?.currentStreak ?? 0) 🔥")
                        StatCard(title: "Longest Streak", value: "\(viewModel.currentUserProfile?.longestStreak ?? 0) 🏆")
                    }
                    .padding(.horizontal)
                    
                    HStack(spacing: 16) {
                        StatCard(title: "Sketches Sent", value: "\(viewModel.currentUserProfile?.drawingCount ?? 0)")
                        StatCard(title: "Reactions", value: "\(viewModel.currentUserProfile?.reactionsReceivedCount ?? 0)")
                    }
                    .padding(.horizontal)
                    
                    // Options
                    VStack(spacing: 0) {
                        NavigationLink(destination: SettingsView()) {
                            ProfileRow(icon: "gearshape.fill", title: "Settings")
                        }
                        Divider().padding(.leading, 48)
                        NavigationLink(destination: Text("Subscription Details")) {
                            ProfileRow(icon: "star.fill", title: "Subscription", iconColor: .yellow)
                        }
                    }
                    .background(Color.white)
                    .cornerRadius(16)
                    .padding(.horizontal)
                    
                    Button(action: {
                        authViewModel.signOut()
                    }) {
                        Text("Log Out")
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white)
                            .cornerRadius(16)
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Profile")
    }
}

struct ProfileRow: View {
    let icon: String
    let title: String
    var iconColor: Color = .pink
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(iconColor)
                .cornerRadius(8)
            
            Text(title)
                .foregroundColor(.primary)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.gray.opacity(0.5))
        }
        .padding()
    }
}
