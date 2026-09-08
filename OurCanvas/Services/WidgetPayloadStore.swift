import Foundation
import FirebaseFirestore
import FirebaseAuth
import UIKit
#if canImport(WidgetKit)
import WidgetKit
#endif

/// App-side widget data pipeline (Phase 3N architecture):
///   MAIN APP resolves the latest drawing + sender name → compact payload in the
///   App Group → WIDGET reads only local storage (no authenticated Firestore).
struct WidgetCirclePayload: Codable, Equatable {
    var groupId: String = ""
    var groupName: String = ""
    var senderName: String = ""
    var drawingImageJPEGBase64: String = ""
    var updatedAt: Date = Date()

    static let empty = WidgetCirclePayload()
}

/// Pure title derivation (tested): what the widget shows for the sender line.
enum WidgetDisplay {
    static func senderLine(payload: WidgetCirclePayload) -> String {
        guard !payload.drawingImageJPEGBase64.isEmpty else { return "No drawings yet" }
        let sender = payload.senderName.isEmpty ? "Someone" : payload.senderName
        return "From \(sender)"
    }

    static func groupLine(payload: WidgetCirclePayload) -> String {
        payload.groupName.isEmpty ? "Our Canvas" : payload.groupName
    }

    static func deepLinkURL(groupId: String) -> URL? {
        var components = URLComponents()
        components.scheme = "ourcanvas"
        components.host = "feed"
        components.queryItems = [URLQueryItem(name: "groupId", value: groupId)]
        return components.url
    }
}

/// App Group bridge. Both targets read `group.com.aapka.prempatra`.
final class WidgetPayloadStore {
    static let appGroupId = "group.com.aapka.prempatra"
    static let selectedGroupIdKey = "selectedGroupId"
    static let payloadKey = "widgetPayload"

    static let shared = WidgetPayloadStore()

    let defaults: UserDefaults?

    init(defaults: UserDefaults? = UserDefaults(suiteName: appGroupId)) {
        self.defaults = defaults
    }

    var selectedGroupId: String? {
        get { defaults?.string(forKey: Self.selectedGroupIdKey) }
        set {
            if let newValue {
                defaults?.set(newValue, forKey: Self.selectedGroupIdKey)
            } else {
                defaults?.removeObject(forKey: Self.selectedGroupIdKey)
            }
        }
    }

    func save(payload: WidgetCirclePayload) {
        if let data = try? JSONEncoder().encode(payload) {
            defaults?.set(data, forKey: Self.payloadKey)
        }
    }

    func loadPayload() -> WidgetCirclePayload {
        guard let data = defaults?.data(forKey: Self.payloadKey),
              let payload = try? JSONDecoder().decode(WidgetCirclePayload.self, from: data) else {
            return .empty
        }
        return payload
    }

    // MARK: - Refresh pipeline (main app only)

    /// Fetches the latest drawing for the selected circle and republishes the payload.
    func refreshSelectedCircleWidget() {
        guard let groupId = selectedGroupId else { return }
        Task {
            do {
                let drawing = try await DrawingRepository().getLatestDrawing(groupId: groupId)
                var payload = WidgetCirclePayload()
                payload.groupId = groupId

                if let groupSnapshot = try? await Firestore.firestore()
                    .collection("groups").document(groupId).getDocument(),
                   let data = groupSnapshot.data() {
                    payload.groupName = FieldCast.string(data["groupName"]) ?? ""
                }

                if let drawing {
                    payload.senderName = await senderName(for: drawing.senderId)
                    payload.drawingImageJPEGBase64 = Self.compactJPEGBase64(from: drawing.drawingData)
                    payload.updatedAt = drawing.sentAt ?? Date()
                }

                save(payload: payload)
                reloadTimelines()
            } catch {
                print("WidgetPayloadStore refresh error: \(error.localizedDescription)")
            }
        }
    }

    private func senderName(for uid: String) async -> String {
        guard let user = (try? await UserRepository.shared.getUser(uid: uid)).flatMap({ $0 }) else {
            return ""
        }
        return user.displayName
    }

    /// Downsamples large base64 images so the App Group stays small.
    static func compactJPEGBase64(from base64: String, maxPixels: CGFloat = 600) -> String {
        guard let data = Data(base64Encoded: base64), let image = UIImage(data: data) else { return "" }
        let scaled = ProfileSetupView.downscaled(image, maxDimension: maxPixels)
        guard let jpeg = scaled.jpegData(compressionQuality: 0.7) else { return "" }
        return jpeg.base64EncodedString()
    }

    private func reloadTimelines() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
