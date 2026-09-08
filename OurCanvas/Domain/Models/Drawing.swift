import Foundation

/// Reaction entry stored at `drawings/{id}.reactions.{uid}`.
/// Field names follow the Android schema: emoji, emojiName, reactedAt, profileUrl
/// (senderName/senderId are kept because the shared Cloud Functions read them).
struct ReactionInfo {
    var emoji: String = ""
    var emojiName: String = ""
    var senderName: String = ""
    var senderId: String = ""
    var profileUrl: String = ""
    var reactedAt: Date? = nil

    static func from(data: [String: Any]) -> ReactionInfo {
        var info = ReactionInfo()
        info.emoji = FieldCast.string(data["emoji"]) ?? ""
        info.emojiName = FieldCast.string(data["emojiName"]) ?? ""
        info.senderName = FieldCast.string(data["senderName"]) ?? ""
        info.senderId = FieldCast.string(data["senderId"]) ?? ""
        info.profileUrl = FieldCast.string(data["profileUrl"]) ?? ""
        info.reactedAt = TimestampCast.date(data["reactedAt"])
        return info
    }
}

/// Firestore `drawings/{id}` model.
/// `recipientIds` is required by the shared Android Cloud Function push fan-out.
/// `stickerData`/`textData` are stored as JSON strings on iOS; Android array payloads are
/// normalized into JSON strings on read (full array parity lands with the drawing engine phase).
struct Drawing: Identifiable {
    var id: String? = nil
    var drawingId: String = ""
    var groupId: String = ""
    var senderId: String = ""
    var recipientIds: [String] = []
    var drawingData: String = ""
    var isFavorite: Bool = false
    var sentAt: Date? = nil
    var strokeData: String = ""
    var stickerData: String = "[]"
    var textData: String = "[]"

    // Legacy single-reaction fields tolerated on read.
    var reaction: String = ""
    var reactionSenderName: String = ""
    var reactionSenderId: String = ""

    var reactions: [String: ReactionInfo] = [:]
}

extension Drawing {
    /// Tolerant decoding; unknown Android-written fields are ignored.
    static func from(documentID: String?, data: [String: Any]) -> Drawing {
        var drawing = Drawing()
        drawing.id = documentID ?? FieldCast.string(data["drawingId"])
        drawing.drawingId = FieldCast.string(data["drawingId"]) ?? documentID ?? ""
        drawing.groupId = FieldCast.string(data["groupId"]) ?? ""
        drawing.senderId = FieldCast.string(data["senderId"]) ?? ""
        drawing.recipientIds = FieldCast.stringArray(data["recipientIds"]) ?? []
        drawing.drawingData = FieldCast.string(data["drawingData"]) ?? ""
        drawing.isFavorite = FieldCast.bool(data["isFavorite"]) ?? false
        drawing.sentAt = TimestampCast.date(data["sentAt"])
        drawing.strokeData = FieldCast.string(data["strokeData"]) ?? ""
        drawing.stickerData = FieldCast.jsonString(from: data["stickerData"]) ?? "[]"
        drawing.textData = FieldCast.jsonString(from: data["textData"]) ?? "[]"
        drawing.reaction = FieldCast.string(data["reaction"]) ?? ""
        drawing.reactionSenderName = FieldCast.string(data["reactionSenderName"]) ?? ""
        drawing.reactionSenderId = FieldCast.string(data["reactionSenderId"]) ?? ""
        if let reactionsRaw = data["reactions"] as? [String: [String: Any]] {
            drawing.reactions = reactionsRaw.mapValues { ReactionInfo.from(data: $0) }
        }
        return drawing
    }
}
