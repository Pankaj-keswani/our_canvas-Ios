import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Combine

/// Notifications hub (Home bell entry). Newest first, capped at 20 visible,
/// unread badge, type icons, deep links, swipe-delete, mark-all-read,
/// clear-all with confirmation, and 30-day auto-cleanup on open.
struct NotificationsView: View {
    @StateObject private var viewModel = NotificationsViewModel()
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SwiftUI.Group {
            if viewModel.isLoading && viewModel.notifications.isEmpty {
                ProgressView("Loading notifications...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.notifications.isEmpty {
                emptyState
            } else {
                notificationList
            }
        }
        .background(BrandBackground())
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Mark all read") { viewModel.markAllRead() }
                    Button("Clear all…", role: .destructive) { viewModel.showClearConfirm = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Clear entire history?", isPresented: $viewModel.showClearConfirm) {
            Button("Clear all", role: .destructive) { viewModel.clearAll() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your entire notification history will be removed. This can't be undone.")
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { viewModel.errorText != nil },
            set: { if !$0 { viewModel.errorText = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorText ?? "")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bell.slash.fill")
                .font(.system(size: 44))
                .foregroundColor(BrandColor.textSecondary)
            Text("No notifications yet")
                .font(.headline)
                .foregroundColor(BrandColor.textPrimary)
            Text("Doodles, reactions and guess results will land here.")
                .font(.subheadline)
                .foregroundColor(BrandColor.textSecondary)
            Spacer()
        }
    }

    private var notificationList: some View {
        List {
            if viewModel.unreadCount > 0 {
                Text("\(viewModel.unreadCount) new")
                    .font(.caption.weight(.bold))
                    .foregroundColor(BrandColor.primary)
                    .listRowBackground(Color.clear)
            }
            ForEach(viewModel.visibleNotifications) { notification in
                Button {
                    viewModel.markRead(notification)
                    router.openDeepLink(notification: notification)
                    dismiss()
                } label: {
                    NotificationRow(notification: notification)
                }
                .listRowBackground(BrandColor.surface.opacity(notification.read ? 0.35 : 0.7))
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        viewModel.delete(notification)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }
}

struct NotificationRow: View {
    let notification: InAppNotification

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(BrandColor.primary.opacity(0.15))
                    .frame(width: 40, height: 40)
                Text(notification.type.emoji)
                    .font(.system(size: 18))
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(notification.title)
                        .font(.subheadline.weight(notification.read ? .regular : .bold))
                        .foregroundColor(BrandColor.textPrimary)
                        .multilineTextAlignment(.leading)
                    if !notification.read {
                        Circle().fill(BrandColor.primary).frame(width: 7, height: 7)
                    }
                }
                Text(notification.body)
                    .font(.caption)
                    .foregroundColor(BrandColor.textSecondary)
                    .multilineTextAlignment(.leading)
                if !notification.groupName.isEmpty {
                    Text(notification.groupName)
                        .font(.caption2)
                        .foregroundColor(BrandColor.textSecondary.opacity(0.7))
                }
                if let date = notification.createdAt {
                    Text(date, style: .relative)
                        .font(.caption2)
                        .foregroundColor(BrandColor.textSecondary.opacity(0.7))
                }
            }
        }
        .padding(.vertical, 2)
    }
}

@MainActor
final class NotificationsViewModel: ObservableObject {
    @Published private(set) var notifications: [InAppNotification] = []
    @Published private(set) var isLoading = true
    @Published private(set) var unreadCount = 0
    @Published var showClearConfirm = false
    @Published var errorText: String?

    private let repository = NotificationRepository()
    private var listener: ListenerRegistration?
    private var didRunCleanup = false

    var uid: String? { Auth.auth().currentUser?.uid }

    var visibleNotifications: [InAppNotification] {
        Array(notifications.prefix(NotificationRepository.displayCap))
    }

    init() {
        startListening()
    }

    deinit {
        listener?.remove()
    }

    func startListening() {
        guard let uid else { return }
        listener = repository.listen(uid: uid) { [weak self] items in
            DispatchQueue.main.async {
                guard let self else { return }
                self.notifications = items
                self.isLoading = false
                self.unreadCount = items.prefix(NotificationRepository.displayCap)
                    .filter { !$0.read }.count
                self.runCleanupIfNeeded()
            }
        }
    }

    private func runCleanupIfNeeded() {
        guard !didRunCleanup else { return }
        didRunCleanup = true
        guard let uid else { return }
        let snapshot = notifications
        Task {
            try? await repository.cleanupExpired(uid: uid, notifications: snapshot)
        }
    }

    func markRead(_ notification: InAppNotification) {
        guard let uid, !notification.read else { return }
        Task {
            do {
                try await repository.markAsRead(uid: uid, notificationId: notification.notificationId)
            } catch {
                errorText = AppError.from(error).message
            }
        }
    }

    func markAllRead() {
        guard let uid else { return }
        let ids = notifications.prefix(NotificationRepository.displayCap).map { $0.notificationId }
        Task {
            do {
                try await repository.markAllRead(uid: uid, notificationIds: ids)
            } catch {
                errorText = AppError.from(error).message
            }
        }
    }

    func delete(_ notification: InAppNotification) {
        guard let uid else { return }
        Task {
            do {
                try await repository.delete(uid: uid, notificationId: notification.notificationId)
            } catch {
                errorText = AppError.from(error).message
            }
        }
    }

    func clearAll() {
        guard let uid else { return }
        let ids = notifications.map { $0.notificationId }
        Task {
            do {
                try await repository.clearAll(uid: uid, notificationIds: ids)
            } catch {
                errorText = AppError.from(error).message
            }
        }
    }
}
