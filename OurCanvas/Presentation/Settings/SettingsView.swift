import SwiftUI
import UIKit
import FirebaseAuth
import Combine

/// Settings (Android A12): real notification toggles, delayed-notification fix,
/// Lifetime Pro row, child-safety/support emails, Terms/Privacy, app version.
struct SettingsView: View {
    @EnvironmentObject var router: AppRouter

    @StateObject private var viewModel = SettingsViewModel()

    @State private var confirmDeleteStep = 0

    private static let childSafetyEmail = "ourcanvasapp@gmail.com"
    private static let supportEmail = "OurCanvasapp@gmail.com"
    private static let privacyURL = "https://prempatra-c91fd.web.app/privacy.html"
    private static let termsURL = "https://prempatra-c91fd.web.app/terms.html"

    var body: some View {
        Form {
            Section(header: Text("Notifications")) {
                Toggle("New doodles", isOn: $viewModel.newDrawingEnabled)
                Toggle("Reactions received", isOn: $viewModel.newReactionEnabled)
                Button {
                    viewModel.fixDelayedNotifications()
                } label: {
                    Label("Fix delayed notifications", systemImage: "bell.badge")
                }
                if let fixMessage = viewModel.fixMessage {
                    Text(fixMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section(header: Text("Account")) {
                NavigationLink {
                    SubscriptionView()
                } label: {
                    HStack {
                        Label("Lifetime Pro", systemImage: "crown.fill")
                            .foregroundColor(BrandColor.warning)
                        Spacer()
                        if viewModel.isPro {
                            Text("PRO")
                                .font(.system(size: 9, weight: .black))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(BrandColor.warning))
                                .foregroundColor(.black)
                        }
                    }
                }
            }

            Section(header: Text("Support")) {
                Button {
                    openMail(to: Self.childSafetyEmail, subject: "Child safety concern")
                } label: {
                    Label("Report Child Safety Concerns", systemImage: "shield.lefthalf.filled")
                }
                Button {
                    openMail(to: Self.supportEmail, subject: "Our Canvas support")
                } label: {
                    Label("Email Support", systemImage: "envelope")
                }
                Button {
                    openURL(Self.termsURL)
                } label: {
                    Label("Terms of Service", systemImage: "doc.text")
                }
                Button {
                    openURL(Self.privacyURL)
                } label: {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
            }

            Section(header: Text("Danger Zone")) {
                Button(role: .destructive) {
                    confirmDeleteStep = 1
                } label: {
                    Label("Delete Account", systemImage: "trash")
                }
            }

            Section {
                Button {
                    router.signOut()
                } label: {
                    Text("Log Out")
                        .foregroundColor(.red)
                }
            } footer: {
                HStack {
                    Spacer()
                    Text("Our Canvas · version \(viewModel.appVersion)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .navigationTitle("Settings")
        .alert("Delete your account?", isPresented: Binding(
            get: { confirmDeleteStep == 1 },
            set: { if !$0 && confirmDeleteStep == 1 { confirmDeleteStep = 0 } }
        )) {
            Button("Continue", role: .destructive) { confirmDeleteStep = 2 }
            Button("Cancel", role: .cancel) { confirmDeleteStep = 0 }
        } message: {
            Text("This permanently deletes your doodles, circles and streaks. Support can't restore deleted accounts.")
        }
        .alert("This is your last chance", isPresented: Binding(
            get: { confirmDeleteStep == 2 },
            set: { if !$0 && confirmDeleteStep == 2 { confirmDeleteStep = 0 } }
        )) {
            Button("Delete everything forever", role: .destructive) {
                confirmDeleteStep = 0
                Task { await viewModel.deleteAccount() }
            }
            Button("Keep my account", role: .cancel) { confirmDeleteStep = 0 }
        } message: {
            Text("Everything you've made in Our Canvas will be gone for good. Are you absolutely sure?")
        }
        .alert("Couldn't delete account", isPresented: Binding(
            get: { viewModel.deleteError != nil },
            set: { if !$0 { viewModel.deleteError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.deleteError ?? "")
        }
    }

    private func openMail(to address: String, subject: String) {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [URLQueryItem(name: "subject", value: subject)]
        if let url = components.url {
            UIApplication.shared.open(url)
        }
    }

    private func openURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var newDrawingEnabled: Bool {
        didSet { savePreferences() }
    }
    @Published var newReactionEnabled: Bool {
        didSet { savePreferences() }
    }
    @Published var fixMessage: String?
    @Published var deleteError: String?

    private(set) var isPro: Bool = false
    let appVersion: String

    private var cancellables = Set<AnyCancellable>()
    private var preferences: NotificationPreferences
    private let deletionService = AccountDeletionService()

    init() {
        let uid = Auth.auth().currentUser?.uid ?? "anonymous"
        let store = UserScopedStore(uid: uid)
        preferences = store.notificationPreferences
        newDrawingEnabled = preferences.newDrawingEnabled
        newReactionEnabled = preferences.newReactionEnabled
        appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

        UserRepository.shared.$currentUserProfile
            .receive(on: RunLoop.main)
            .sink { [weak self] profile in
                self?.isPro = profile?.isPro ?? false
            }
            .store(in: &cancellables)
    }

    func savePreferences() {
        var store = UserScopedStore(uid: Auth.auth().currentUser?.uid ?? "anonymous")
        preferences.newDrawingEnabled = newDrawingEnabled
        preferences.newReactionEnabled = newReactionEnabled
        store.notificationPreferences = preferences
    }

    /// Re-requests registration + refreshes the FCM token association + flushes the
    /// widget payload (best-effort iOS-side fix for delayed notifications).
    func fixDelayedNotifications() {
        NotificationManager.shared.requestAuthorizationIfNeeded()
        if let uid = Auth.auth().currentUser?.uid {
            PushTokenStore.shared.userDidAuthenticate(uid: uid)
        }
        WidgetPayloadStore.shared.refreshSelectedCircleWidget()
        fixMessage = "Done — notifications re-registered. If pushes stay delayed, check Settings → Notifications → Our Canvas."
    }

    func deleteAccount() async {
        do {
            try await deletionService.deleteEverything()
            routerSignOut()
        } catch {
            deleteError = AppError.from(error).message
        }
    }

    private func routerSignOut() {
        AppRouter.shared?.signOut()
    }
}
