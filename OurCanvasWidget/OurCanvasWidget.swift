import WidgetKit
import SwiftUI
import AppIntents

/// Shared App Group contract (mirrors the app-side WidgetPayloadStore constants —
/// the two targets deliberately share no code, only the App Group container).
private enum SharedWidgetContract {
    static let appGroupId = "group.com.aapka.prempatra"
    static let selectedGroupIdKey = "selectedGroupId"
    static let payloadKey = "widgetPayload"

    static func deepLinkURL(groupId: String) -> URL? {
        var components = URLComponents()
        components.scheme = "ourcanvas"
        components.host = "feed"
        components.queryItems = [URLQueryItem(name: "groupId", value: groupId)]
        return components.url
    }
}

/// Our Canvas home-screen widget (Phase 3N).
///
/// ARCHITECTURE: the widget reads ONLY the App Group payload written by the main
/// app (latest drawing + sender + circle) — it never touches an authenticated
/// Firestore session. The main app refreshes the payload on foreground and on
/// push delivery; the widget contributes hourly timeline entries plus (on iOS 17+)
/// an interactive manual-refresh AppIntent button.
struct OurCanvasWidgetEntry: TimelineEntry {
    let date: Date
    let hasSelection: Bool
    let image: UIImage?
    let senderLine: String
    let groupLine: String
    let deepLinkURL: URL?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> OurCanvasWidgetEntry {
        OurCanvasWidgetEntry(date: Date(),
                             hasSelection: true,
                             image: nil,
                             senderLine: "From your circle",
                             groupLine: "Our Canvas",
                             deepLinkURL: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (OurCanvasWidgetEntry) -> ()) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<OurCanvasWidgetEntry>) -> ()) {
        let entry = currentEntry()
        // Multiple forward entries + refresh-after policy (never a lone .atEnd placeholder).
        var entries: [OurCanvasWidgetEntry] = [entry]
        for hourOffset in 1...6 {
            entries.append(OurCanvasWidgetEntry(date: Calendar.current.date(byAdding: .hour,
                                                                           value: hourOffset,
                                                                           to: Date()) ?? Date(),
                                                hasSelection: entry.hasSelection,
                                                image: entry.image,
                                                senderLine: entry.senderLine,
                                                groupLine: entry.groupLine,
                                                deepLinkURL: entry.deepLinkURL))
        }
        completion(Timeline(entries: entries,
                            policy: .after(Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date())))
    }

    private func currentEntry() -> OurCanvasWidgetEntry {
        guard let defaults = UserDefaults(suiteName: SharedWidgetContract.appGroupId) else {
            return OurCanvasWidgetEntry(date: Date(), hasSelection: false, image: nil,
                                        senderLine: "", groupLine: "", deepLinkURL: nil)
        }

        // Payload decode mirrors the app-side Codable shape without sharing targets.
        guard let data = defaults.data(forKey: SharedWidgetContract.payloadKey),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let hasSelection = !(defaults.string(forKey: SharedWidgetContract.selectedGroupIdKey) ?? "").isEmpty
            return OurCanvasWidgetEntry(date: Date(),
                                        hasSelection: hasSelection,
                                        image: nil,
                                        senderLine: hasSelection ? "No drawings yet" : "",
                                        groupLine: "",
                                        deepLinkURL: nil)
        }

        let groupId = raw["groupId"] as? String ?? ""
        let groupName = raw["groupName"] as? String ?? ""
        let senderName = raw["senderName"] as? String ?? ""
        let imageBase64 = raw["drawingImageJPEGBase64"] as? String ?? ""

        var image: UIImage?
        if let imageData = Data(base64Encoded: imageBase64) {
            image = UIImage(data: imageData)
        }

        let senderLine: String
        if imageBase64.isEmpty {
            senderLine = "No drawings yet"
        } else {
            senderLine = "From \(senderName.isEmpty ? "Someone" : senderName)"
        }

        return OurCanvasWidgetEntry(date: Date(),
                                    hasSelection: !groupId.isEmpty,
                                    image: image,
                                    senderLine: senderLine,
                                    groupLine: groupName.isEmpty ? "Our Canvas" : groupName,
                                    deepLinkURL: groupId.isEmpty ? nil : SharedWidgetContract.deepLinkURL(groupId: groupId))
    }
}

struct OurCanvasWidgetEntryView: View {
    @Environment(\.widgetFamily) private var widgetFamily
    var entry: Provider.Entry

    var body: some View {
        content
            .widgetURL(entry.deepLinkURL)
            .modifier(WidgetBackground())
    }

    @ViewBuilder
    private var content: some View {
        if entry.hasSelection {
            VStack(alignment: .leading, spacing: 6) {
                if let image = entry.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: widgetFamily == .systemSmall ? 110 : .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Spacer(minLength: 4)
                    Text("🎨")
                        .font(.system(size: 34))
                    Spacer(minLength: 4)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.senderLine)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(entry.groupLine)
                            .font(.system(size: 10, design: .rounded))
                            .foregroundColor(.white.opacity(0.65))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        WidgetRefreshIfAvailable()
                    }
                }
            }
            .padding(10)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "paintpalette.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 0.23, green: 0.85, blue: 0.82),
                                                             Color(red: 0.67, green: 0.37, blue: 0.98)],
                                                    startPoint: .leading, endPoint: .trailing))
                Text("Pick a circle in the app to light up this widget")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            .padding(12)
        }
    }
}

@main
struct OurCanvasWidget: Widget {
    let kind: String = "OurCanvasWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            OurCanvasWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Our Canvas")
        .description("See the latest drawing from your circle.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - iOS 16-safe background (containerBackground is iOS 17+)

struct WidgetBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOSApplicationExtension 17.0, iOS 17.0, *) {
            content.containerBackground(for: .widget) {
                Color(red: 0.06, green: 0.08, blue: 0.15)
            }
        } else {
            content.background(Color(red: 0.06, green: 0.08, blue: 0.15))
        }
    }
}

// MARK: - Manual refresh (iOS 17+ interactive widgets only)

/// Refreshes the timeline from inside the widget process. On iOS 16 the button is
/// not rendered (interactive widgets require iOS 17) — the fallback is the
/// timeline policy plus app-triggered reloads.
struct RefreshWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh Doodle"
    static let description = IntentDescription("Fetch the latest doodle for your circle.")

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct WidgetRefreshButton: View {
    var body: some View {
        Button(intent: RefreshWidgetIntent()) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.white)
        }
        .buttonStyle(.borderless)
    }
}

/// Renders the interactive refresh button only on iOS 17+.
struct WidgetRefreshIfAvailable: View {
    var body: some View {
        if #available(iOSApplicationExtension 17.0, iOS 17.0, *) {
            WidgetRefreshButton()
        } else {
            EmptyView()
        }
    }
}
