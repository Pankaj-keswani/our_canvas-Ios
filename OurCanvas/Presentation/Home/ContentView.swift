import SwiftUI
import FirebaseAuth

struct ContentView: View {
    @StateObject private var authViewModel = AuthViewModel()
    
    var body: some View {
        SwiftUI.Group {
            if authViewModel.userSession != nil {
                MainTabView()
            } else {
                AuthView()
            }
        }
        .environmentObject(authViewModel)
    }
}

struct MainTabView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Image(systemName: "house.fill")
                Text("Home")
            }
            .tag(0)
            
            NavigationStack {
                GroupsView()
            }
            .tabItem {
                Image(systemName: "person.2.fill")
                Text("Circles")
            }
            .tag(1)
            
            NavigationStack {
                ProfileView()
            }
            .tabItem {
                Image(systemName: "person.crop.circle.fill")
                Text("Profile")
            }
            .tag(2)
        }
        .tint(.pink)
    }
}
