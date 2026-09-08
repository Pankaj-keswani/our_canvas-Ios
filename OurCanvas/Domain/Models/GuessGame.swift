import Foundation

/// `guess_games/{gameId}` model — field names match the Android production schema
/// exactly (spec A5.1/A14). Unknown fields decode safely; missing fields default.
struct GuessGame: Equatable, Identifiable {
    enum Status: String {
        case drawing = "DRAWING"
        case guessing = "GUESSING"
        case finished = "FINISHED"

        static func from(_ raw: String?) -> Status {
            Status(rawValue: raw ?? "") ?? .drawing
        }
    }

    enum RoundResult: String {
        case correct = "CORRECT"
        case gaveUp = "GAVE_UP"

        static func from(_ raw: String?) -> RoundResult? {
            guard let raw else { return nil }
            return RoundResult(rawValue: raw)
        }
    }

    struct Attempt: Equatable {
        var userId: String = ""
        var userName: String = ""
        var guess: String = ""
        var guessedAt: Date? = nil

        static func from(data: [String: Any]) -> Attempt {
            var attempt = Attempt()
            attempt.userId = FieldCast.string(data["userId"]) ?? ""
            attempt.userName = FieldCast.string(data["userName"]) ?? ""
            attempt.guess = FieldCast.string(data["guess"]) ?? ""
            attempt.guessedAt = TimestampCast.date(data["guessedAt"])
            return attempt
        }
    }

    let id: String
    let groupId: String
    let status: Status
    let drawerId: String
    let drawerName: String
    let winnerId: String?
    let winnerName: String?
    let gaveUpUsers: [String]
    let memberIds: [String]
    let wordHint: String
    let letterBank: [String]
    let wordLength: Int
    let strokeData: String
    let attempts: [Attempt]
    let result: RoundResult?
    let revealedWord: String?
    /// Legacy 1v1 games carry a non-blank guesserId (mixed-version compatibility).
    let guesserId: String?
    let createdAt: Date?
    let updatedAt: Date?

    var isLegacy: Bool {
        if let guesserId, !guesserId.trimmed.isEmpty { return true }
        return false
    }

    var recentAttempts: [Attempt] {
        Array(attempts.suffix(8))
    }

    /// Winner draws next; when nobody cracked it (all gave up) the drawer keeps the pen.
    var nextDrawerId: String {
        if result == .gaveUp { return drawerId }
        if let winnerId, !winnerId.isEmpty { return winnerId }
        return drawerId
    }

    var nextDrawerName: String {
        if result == .gaveUp { return drawerName }
        if let winnerName, !winnerName.isEmpty { return winnerName }
        return drawerName
    }

    static func from(documentID: String, data: [String: Any]) -> GuessGame {
        GuessGame(
            id: documentID,
            groupId: FieldCast.string(data["groupId"]) ?? "",
            status: Status.from(FieldCast.string(data["status"])),
            drawerId: FieldCast.string(data["drawerId"]) ?? "",
            drawerName: FieldCast.string(data["drawerName"]) ?? "Someone",
            winnerId: FieldCast.string(data["winnerId"]),
            winnerName: FieldCast.string(data["winnerName"]),
            gaveUpUsers: FieldCast.stringArray(data["gaveUpUsers"]) ?? [],
            memberIds: FieldCast.stringArray(data["memberIds"]) ?? [],
            wordHint: FieldCast.string(data["wordHint"]) ?? "",
            letterBank: FieldCast.stringArray(data["letterBank"]) ?? [],
            wordLength: FieldCast.int(data["wordLength"]) ?? 0,
            strokeData: FieldCast.string(data["strokeData"]) ?? "",
            attempts: (data["attempts"] as? [[String: Any]] ?? []).map { Attempt.from(data: $0) },
            result: RoundResult.from(FieldCast.string(data["result"])),
            revealedWord: FieldCast.string(data["revealedWord"]),
            guesserId: FieldCast.string(data["guesserId"]),
            createdAt: TimestampCast.date(data["createdAt"]),
            updatedAt: TimestampCast.date(data["updatedAt"])
        )
    }
}

// MARK: - Card state machine (pure derivation, tested)

enum GuessCardState: Equatable {
    /// No round in this circle yet — StartCard.
    case noGame
    /// Drawer's own card while the round is in DRAWING (word recall included).
    case drawingAsDrawer(game: GuessGame, word: String?)
    /// Everyone else while the round is in DRAWING — WaitingCard.
    case drawingWaiting(game: GuessGame)
    /// Multiplayer guessing (eligible guesser, hasn't revealed).
    case guessing(game: GuessGame, revealedLocally: Bool)
    /// This user revealed — spectate until the round finishes.
    case gaveUpSpectate(game: GuessGame, revealedWord: String)
    /// Legacy 1v1: this user is the designated guesser.
    case legacyGuessing(game: GuessGame)
    /// Legacy 1v1: everyone else spectates.
    case legacySpectator(game: GuessGame)
    /// Round over — FinishedCard (CTA above the replay).
    case finished(game: GuessGame)

    static func derive(game: GuessGame?,
                       uid: String,
                       localRevealedWord: String?) -> GuessCardState {
        guard let game else { return .noGame }

        if game.status == .finished {
            return .finished(game: game)
        }

        // Legacy 1v1 compatibility: non-blank guesserId renders the old flow.
        if game.isLegacy {
            if game.guesserId == uid {
                return .legacyGuessing(game: game)
            }
            return .legacySpectator(game: game)
        }

        if game.drawerId == uid {
            return .drawingAsDrawer(game: game, word: nil)
        }

        if game.status == .drawing {
            return .drawingWaiting(game: game)
        }

        // GUESSING — non-drawer member.
        if let localRevealedWord {
            return .gaveUpSpectate(game: game, revealedWord: localRevealedWord)
        }
        if game.gaveUpUsers.contains(uid) {
            // Server knows this user gave up; word arrives from the worker response,
            // but if only the flag arrived, spectate without the word displayed.
            return .gaveUpSpectate(game: game, revealedWord: "")
        }
        return .guessing(game: game, revealedLocally: false)
    }
}

// MARK: - 24-hour takeover (pure logic, tested)

enum GuessTakeover {
    /// Android `TURN_TAKEOVER_MS` = 24 hours.
    static let takeoverInterval: TimeInterval = 24 * 60 * 60

    static func canTakeOver(game: GuessGame, uid: String, now: Date = Date()) -> Bool {
        guard game.status == .drawing, game.drawerId != uid else { return false }
        let reference = game.updatedAt ?? game.createdAt ?? now
        return now.timeIntervalSince(reference) >= takeoverInterval
    }
}

// MARK: - Word bank (word → category pairs; spec A5.1 ~70 entries)

enum WordBank {
    struct Pair: Equatable {
        let word: String
        let category: String
    }

    static let pairs: [Pair] = [
        Pair(word: "cat", category: "Animal"),
        Pair(word: "dog", category: "Animal"),
        Pair(word: "elephant", category: "Animal"),
        Pair(word: "giraffe", category: "Animal"),
        Pair(word: "penguin", category: "Animal"),
        Pair(word: "butterfly", category: "Animal"),
        Pair(word: "dolphin", category: "Animal"),
        Pair(word: "rabbit", category: "Animal"),
        Pair(word: "snail", category: "Animal"),
        Pair(word: "owl", category: "Animal"),
        Pair(word: "apple", category: "Food"),
        Pair(word: "banana", category: "Food"),
        Pair(word: "pizza", category: "Food"),
        Pair(word: "burger", category: "Food"),
        Pair(word: "icecream", category: "Food"),
        Pair(word: "donut", category: "Food"),
        Pair(word: "carrot", category: "Food"),
        Pair(word: "popcorn", category: "Food"),
        Pair(word: "pancake", category: "Food"),
        Pair(word: "watermelon", category: "Food"),
        Pair(word: "house", category: "Place"),
        Pair(word: "castle", category: "Place"),
        Pair(word: "bridge", category: "Place"),
        Pair(word: "lighthouse", category: "Place"),
        Pair(word: "tent", category: "Place"),
        Pair(word: "school", category: "Place"),
        Pair(word: "hospital", category: "Place"),
        Pair(word: "airport", category: "Place"),
        Pair(word: "island", category: "Place"),
        Pair(word: "pyramid", category: "Place"),
        Pair(word: "car", category: "Object"),
        Pair(word: "bicycle", category: "Object"),
        Pair(word: "train", category: "Object"),
        Pair(word: "airplane", category: "Object"),
        Pair(word: "boat", category: "Object"),
        Pair(word: "rocket", category: "Object"),
        Pair(word: "umbrella", category: "Object"),
        Pair(word: "glasses", category: "Object"),
        Pair(word: "scissors", category: "Object"),
        Pair(word: "ladder", category: "Object"),
        Pair(word: "balloon", category: "Object"),
        Pair(word: "guitar", category: "Object"),
        Pair(word: "camera", category: "Object"),
        Pair(word: "clock", category: "Object"),
        Pair(word: "key", category: "Object"),
        Pair(word: "crown", category: "Object"),
        Pair(word: "tree", category: "Nature"),
        Pair(word: "flower", category: "Nature"),
        Pair(word: "sun", category: "Nature"),
        Pair(word: "moon", category: "Nature"),
        Pair(word: "star", category: "Nature"),
        Pair(word: "rainbow", category: "Nature"),
        Pair(word: "cloud", category: "Nature"),
        Pair(word: "mountain", category: "Nature"),
        Pair(word: "ocean", category: "Nature"),
        Pair(word: "volcano", category: "Nature"),
        Pair(word: "cactus", category: "Nature"),
        Pair(word: "snowman", category: "Nature"),
        Pair(word: "soccer", category: "Sport"),
        Pair(word: "cricket", category: "Sport"),
        Pair(word: "tennis", category: "Sport"),
        Pair(word: "basketball", category: "Sport"),
        Pair(word: "swimming", category: "Sport"),
        Pair(word: "cycling", category: "Sport"),
        Pair(word: "skateboard", category: "Sport"),
        Pair(word: "trophy", category: "Sport"),
        Pair(word: "smile", category: "Emoji"),
        Pair(word: "heart", category: "Emoji"),
        Pair(word: "ghost", category: "Emoji"),
        Pair(word: "unicorn", category: "Emoji"),
        Pair(word: "robot", category: "Emoji"),
        Pair(word: "dragon", category: "Emoji"),
        Pair(word: "mermaid", category: "Emoji"),
    ]

    static func randomPair() -> Pair {
        pairs.randomElement() ?? Pair(word: "cat", category: "Animal")
    }
}

// MARK: - Letter bank construction (seeded stable shuffle, tested)

enum LetterBankBuilder {
    /// Android decoy letter pool (spec A5.1).
    static let decoyPool = Array("AEIOURSTLNMCPD")

    /// Letters of the word + decoys, shuffled deterministically from the gameId hash
    /// so every client shows the exact same bank.
    static func build(word: String, gameId: String) -> [String] {
        let normalized = GuessNormalizer.normalize(word)
        var tiles: [String] = normalized.map { String($0) }
        tiles.append(contentsOf: decoyPool.map { String($0) })
        return seededShuffle(tiles, seed: seedHash(gameId))
    }

    /// djb2 hash — stable across platforms/languages.
    static func seedHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in string.utf8 {
            hash = ((hash &<< 5) &+ hash) &+ UInt64(byte)
        }
        return hash
    }

    static func seededShuffle<T>(_ items: [T], seed: UInt64) -> [T] {
        var array = items
        var random = SeededRandom(seed: seed)
        if array.count > 1 {
            for i in stride(from: array.count - 1, to: 0, by: -1) {
                let j = Int(random.next() * Double(i + 1))
                array.swapAt(i, j)
            }
        }
        return array
    }
}

/// Guess/word normalization shared with the worker semantics: lowercase letters only.
enum GuessNormalizer {
    /// Lowercase ASCII letters only — the word bank and worker comparison vocabulary.
    static func normalize(_ input: String) -> String {
        String(input.lowercased().filter { $0.isLetter && $0.isASCII })
    }
}

/// Maps a worker judge response to the UI action (pure, tested). The worker is
/// authoritative — this only interprets its verdict.
enum GuessOutcomeAction: Equatable {
    case correct
    case lostRace(winnerName: String)
    case wrong
    case revealed(word: String)
    case none

    static func action(for result: JudgeResult) -> GuessOutcomeAction {
        if result.correct { return .correct }
        if result.lostRace { return .lostRace(winnerName: result.winnerName ?? "someone") }
        if result.gaveUp, let word = result.word { return .revealed(word: word) }
        if result.gaveUp { return .none }
        return .wrong
    }
}
