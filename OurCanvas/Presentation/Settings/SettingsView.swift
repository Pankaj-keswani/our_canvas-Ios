import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var router: AppRouter

    var body: some View {
        Form {
            Section(header: Text("Account")) {
                Button("Delete Account") {
                    // Triggers delete account flow (arrives with the Profile phase)
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
                    router.signOut()
                }
                .foregroundColor(.red)
            }
        }
        .navigationTitle("Settings")
    }
}
