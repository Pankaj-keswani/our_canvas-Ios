import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @StateObject private var storeManager = StoreManager()
    
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color.pink.opacity(0.1), Color.blue.opacity(0.1)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ).ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(viewModel.greeting)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Text(viewModel.userName)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                
                                if storeManager.isPro {
                                    Text("PRO")
                                        .font(.system(size: 10, weight: .black))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.yellow)
                                        .foregroundColor(.black)
                                        .cornerRadius(4)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        NavigationLink(destination: SettingsView()) {
                            Image(systemName: "gearshape.fill")
                                .foregroundColor(.gray)
                                .font(.title3)
                                .padding(8)
                                .background(Color.white.opacity(0.5))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 16)
                    
                    // Stats
                    HStack(spacing: 16) {
                        StatCard(title: "Streaks", value: "\(viewModel.currentUserProfile?.currentStreak ?? 0) 🔥")
                        StatCard(title: "Sketches", value: "\(viewModel.currentUserProfile?.drawingCount ?? 0) ✏️")
                        StatCard(title: "Circles", value: "\(viewModel.groups.count) ⭕")
                    }
                    .padding(.horizontal)
                    
                    // Widget Tip
                    VStack(alignment: .leading) {
                        Text("💡 Tip: Add the Our Canvas Widget")
                            .font(.headline)
                        Text("Add our widget to your home screen to see the latest drawings from your circles directly on your home screen.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                    .padding(.horizontal)
                    
                    // Circles Section Header
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your Circles")
                            .font(.title3)
                            .fontWeight(.bold)
                        Text("Tap a circle to open its feed")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    
                    // Groups List
                    if viewModel.isLoading && viewModel.groups.isEmpty {
                        ProgressView()
                            .padding(.top, 40)
                    } else if viewModel.groups.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "person.3.sequence.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.gray.opacity(0.5))
                            Text("You haven't joined any circles yet.")
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 40)
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
                .padding(.bottom, 30)
            }
            .refreshable {
                viewModel.refreshGroups()
            }
        }
        .navigationTitle("")
        .navigationBarHidden(true)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.headline)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}
