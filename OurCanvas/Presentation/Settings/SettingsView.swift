import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    
    var body: some View {
        Form {
            Section(header: Text("Account")) {
                Button("Delete Account") {
                    // Triggers delete account flow
                }
                .foregroundColor(.red)
            }
            
            Section(header: Text("App Settings")) {
                Toggle("Notifications", isOn: .constant(true))
            }
            
            Section(header: Text("Support")) {
                Button("Contact Us") { }
                Button("Terms of Service") { }
                Button("Privacy Policy") { }
            }
            
            Section {
                Button("Log Out") {
                    authViewModel.signOut()
                }
                .foregroundColor(.red)
            }
        }
        .navigationTitle("Settings")
    }
}
