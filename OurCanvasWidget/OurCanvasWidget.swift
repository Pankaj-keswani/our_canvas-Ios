import WidgetKit
import SwiftUI
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), image: nil, senderName: "Pankaj", groupName: "Our Canvas", reaction: "❤️")
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(date: Date(), image: nil, senderName: "Pankaj", groupName: "Our Canvas", reaction: nil)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        
        let db = Firestore.firestore()
        let defaults = UserDefaults(suiteName: "group.com.aapka.prempatra")
        let groupId = defaults?.string(forKey: "selectedGroupId") ?? ""
        
        if groupId.isEmpty {
            let entry = SimpleEntry(date: Date(), image: nil, senderName: "No Circle Selected", groupName: "", reaction: nil)
            let timeline = Timeline(entries: [entry], policy: .atEnd)
            completion(timeline)
            return
        }
        
        db.collection("drawings")
            .whereField("groupId", isEqualTo: groupId)
            .order(by: "sentAt", descending: true)
            .limit(to: 1)
            .getDocuments { snapshot, error in
                guard let document = snapshot?.documents.first else {
                    let entry = SimpleEntry(date: Date(), image: nil, senderName: "No drawings yet", groupName: "", reaction: nil)
                    completion(Timeline(entries: [entry], policy: .atEnd))
                    return
                }
                
                let drawingData = document.data()["drawingData"] as? String ?? ""
                let senderId = document.data()["senderId"] as? String ?? "Someone"
                var uiImage: UIImage? = nil
                
                if let data = Data(base64Encoded: drawingData) {
                    uiImage = UIImage(data: data)
                }
                
                // Note: Production widget would fetch user profile to get real display name
                let entry = SimpleEntry(date: Date(), image: uiImage, senderName: "From \(senderId)", groupName: "Circle", reaction: nil)
                let timeline = Timeline(entries: [entry], policy: .atEnd)
                completion(timeline)
            }
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let image: UIImage?
    let senderName: String
    let groupName: String
    let reaction: String?
}

struct OurCanvasWidgetEntryView : View {
    var entry: Provider.Entry

    var body: some View {
        ZStack {
            Color(red: 247/255, green: 249/255, blue: 251/255)
            
            if let image = entry.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(12)
            } else {
                Text("Waiting for drawing...")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
            
            VStack {
                Spacer()
                HStack {
                    Text(entry.senderName)
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(6)
                        .background(Color.white.opacity(0.8))
                        .cornerRadius(8)
                    Spacer()
                    if let reaction = entry.reaction {
                        Text(reaction)
                            .font(.caption)
                            .padding(6)
                            .background(Color.white)
                            .clipShape(Circle())
                            .shadow(radius: 2)
                    }
                }
                .padding(8)
            }
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
        .supportedFamilies([.systemSmall, .systemLarge])
    }
}
