import Foundation

/// `users/{uid}/notifications/{notificationId}` model — exact Android field names
/// (spec A6.2/A9.4). Unknown fields decode safely; missing fields default.
struct InAppNotification: Equatable, Identifiable {
    enum NotificationType: String {
        case newDrawing = "NEW_DRAWING"
        case newReaction = "NEW_REACTION"
        case guessResult = "GUESS_RESULT"

        static func from(_ raw: String?) -> NotificationType? {
            guard let raw else { return nil }
            return NotificationType(rawValue: raw)
        }

        var emoji: String {
            switch self {
            case .newDrawing: return "🎨"
            case .newReaction: return "❤️"
            case .guessResult: return "🎮"
            }
        }
    }

    var notificationId: String = ""
    var type: NotificationType = .newDrawing
    var title: String = ""
    var body: String = ""
    var createdAt: Date? = nil
    var read: Bool = false
    var senderId: String = ""
    var senderName: String = ""
    var groupId: String = ""
    var groupName: String = ""
    var drawingId: String = ""
    var reactionEmoji: String = ""
    var targetId: String = ""
    var recipientId: String = ""

    var id: String { notificationId }

    static func from(documentID: String, data: [String: Any]) -> InAppNotification {
        var notification = InAppNotification()
        notification.notificationId = FieldCast.string(data["notificationId"]) ?? documentID
        notification.type = NotificationType.from(FieldCast.string(data["type"])) ?? .newDrawing
        notification.title = FieldCast.string(data["title"]) ?? ""
        notification.body = FieldCast.string(data["body"]) ?? ""
        notification.createdAt = TimestampCast.date(data["createdAt"])
        notification.read = FieldCast.bool(data["read"]) ?? false
        notification.senderId = FieldCast.string(data["senderId"]) ?? ""
        notification.senderName = FieldCast.string(data["senderName"]) ?? ""
        notification.groupId = FieldCast.string(data["groupId"]) ?? ""
        notification.groupName = FieldCast.string(data["groupName"]) ?? ""
        notification.drawingId = FieldCast.string(data["drawingId"]) ?? ""
        notification.reactionEmoji = FieldCast.string(data["reactionEmoji"]) ?? ""
        notification.targetId = FieldCast.string(data["targetId"]) ?? ""
        notification.recipientId = FieldCast.string(data["recipientId"]) ?? ""
        return notification
    }

    func fields() -> [String: Any] {
        [
            "notificationId": notificationId,
            "type": type.rawValue,
            "title": title,
            "body": body,
            "createdAt": createdAt.map { Timestamp(date: $0) } ?? FieldValue.serverTimestamp(),
            "read": read,
            "senderId": senderId,
            "senderName": senderName,
            "groupId": groupId,
            "groupName": groupName,
            "drawingId": drawingId,
            "reactionEmoji": reactionEmoji,
            "targetId": targetId,
            "recipientId": recipientId,
        ]
    }

    /// Android-compatible notification IDs (stable per event → dedupe via doc ID).
    static func makeId(type: NotificationType, drawingId: String = "", gameId: String = "", senderId: String = "") -> String {
        switch type {
        case .newDrawing:
            return "drawing:\(drawingId)"
        case .newReaction:
            return "reaction:\(drawingId):\(senderId)"
        case .guessResult:
            return "guess:\(gameId.isEmpty ? targetIdFallback : gameId)"
        }
    }

    private static var targetIdFallback: String { UUID().uuidString }
}

// MARK: - Push payload contract (4 types, validated + defaulted)

/// Parsed FCM data payload. Pure parser — unit tested against the Android contract.
struct PushPayload: Equatable {
    enum PushType: String {
        case newDrawing = "new_drawing"
        case newReaction = "new_reaction"
        case newGameTurn = "new_game_turn"
        case guessResult = "guess_result"
    }

    enum GuessPerspective: String {
        case drawer
        case guesser
    }

    var type: PushType
    var senderName: String = "Someone"
    var reactorName: String = ""
    var groupId: String = ""
    var groupName: String = "your circle"
    var drawingId: String = ""
    var emoji: String = ""
    // guess_result extras
    var result: String = ""
    var word: String = ""
    var winnerName: String = ""
    var perspective: String = ""

    /// Android `parseAndValidatePayload` parity: type whitelist + friendly defaults.
    /// Returns nil for payloads without a known type.
    static func parse(_ userInfo: [AnyHashable: Any]) -> PushPayload? {
        func string(_ key: String) -> String? {
            userInfo[key] as? String
        }

        guard let typeRaw = string("type"),
              let type = PushType(rawValue: typeRaw) else {
            return nil
        }

        var payload = PushPayload(type: type)
        payload.senderName = nonEmpty(string("senderName")) ?? "Someone"
        payload.reactorName = nonEmpty(string("reactorName")) ?? payload.senderName
        payload.groupId = string("groupId") ?? string("gId") ?? ""
        payload.groupName = nonEmpty(string("groupName")) ?? "your circle"
        payload.drawingId = string("drawingId") ?? ""
        payload.emoji = string("emoji") ?? ""
        payload.result = string("result") ?? ""
        payload.word = string("word") ?? ""
        payload.winnerName = string("winnerName") ?? ""
        payload.perspective = string("perspective") ?? ""
        return payload
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmed.isEmpty else { return nil }
        return value
    }

    // MARK: - In-app notification mapping (role-aware copy, Android A9.4)

    /// Builds the receiver-side in-app notification for the CURRENT user only.
    /// The worker is authoritative for who receives what; the client only persists
    /// its own copy. Guess-result copy is role-aware and falls back to legacy copy
    /// when winnerName is missing.
    func toInAppNotification(recipientId: String) -> InAppNotification {
        var notification = InAppNotification()
        notification.recipientId = recipientId
        notification.senderId = ""
        notification.senderName = senderName
        notification.groupId = groupId
        notification.groupName = groupName
        notification.drawingId = drawingId
        notification.targetId = drawingId
        notification.reactionEmoji = emoji

        switch type {
        case .newDrawing:
            notification.type = .newDrawing
            notification.notificationId = InAppNotification.makeId(type: .newDrawing, drawingId: drawingId)
            notification.title = "New doodle from \(senderName) 🎨"
            notification.body = "\(senderName) sent a doodle to \(groupName)!"
        case .newReaction:
            notification.type = .newReaction
            notification.notificationId = InAppNotification.makeId(type: .newReaction, drawingId: drawingId, senderId: senderName)
            notification.title = "\(reactorName) reacted \(emoji.isEmpty ? "❤️" : emoji)"
            notification.body = "\(reactorName) reacted to your doodle in \(groupName)!"
        case .newGameTurn:
            notification.type = .guessResult
            notification.notificationId = InAppNotification.makeId(type: .guessResult, gameId: drawingId)
            notification.title = "🎮 Guess My Doodle"
            notification.body = "\(senderName) drew a mystery doodle in \(groupName) — be the first to guess it!"
        case .guessResult:
            notification.type = .guessResult
            notification.notificationId = InAppNotification.makeId(type: .guessResult, gameId: targetIdForGame)
            notification.title = "🎮 Guess My Doodle"
            notification.body = guessResultBody
        }
        return notification
    }

    private var targetIdForGame: String {
        // Game id arrives as drawingId/targetId depending on the worker event.
        drawingId.isEmpty ? winnerName : drawingId
    }

    /// Role-aware copy (perspective: drawer | guesser). The word is only shown for
    /// outcomes the worker decided this recipient may see — we render exactly what
    /// the payload carries, never more.
    var guessResultBody: String {
        let displayWinner = winnerName.isEmpty ? "Someone" : winnerName
        let wordClause = word.isEmpty ? "" : " The word was \(word)."

        if result == "GAVE_UP" || result == "gave_up" {
            return perspective == GuessPerspective.drawer.rawValue
                ? "😌 Nobody cracked it — you keep the pen! ✏️"
                : "Nobody cracked this one — new round incoming! ✏️"
        }

        if winnerName.isEmpty {
            return "Round over — check who won!\(wordClause)"
        }

        return perspective == GuessPerspective.drawer.rawValue
            ? "🏆 \(displayWinner) cracked your doodle!\(wordClause) Their turn to draw 🎨"
            : "⚡ \(displayWinner) guessed it first!\(wordClause)"
    }

    // MARK: - Deep link mapping (route=drawing_feed contract)

    func deepLinkURL() -> URL? {
        var components = URLComponents()
        components.scheme = "ourcanvas"
        var params: [String: String] = [:]
        switch type {
        case .newGameTurn, .guessResult:
            if !targetIdForGame.isEmpty {
                params["gameId"] = targetIdForGame
            }
            if !groupId.isEmpty {
                params["groupId"] = groupId
                params["route"] = "drawing_feed"
            }
        default:
            params["route"] = "drawing_feed"
            params["groupId"] = groupId
            if !groupName.isEmpty { params["groupName"] = groupName }
            if !drawingId.isEmpty { params["drawingId"] = drawingId }
        }
        components.host = "feed"
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url
    }
}
