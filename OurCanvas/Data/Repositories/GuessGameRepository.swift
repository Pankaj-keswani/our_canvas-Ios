import Foundation
import FirebaseFirestore
import FirebaseAuth

/// Repository for `guess_games`. All state transitions other than judging go through
/// Firestore; JUDGING goes exclusively through the Cloudflare Worker (authoritative).
final class GuessGameRepository {

    private let db = Firestore.firestore()
    private let judge: GuessJudging

    init(judge: GuessJudging = WorkerJudgeClient()) {
        self.judge = judge
    }

    // MARK: - Listening

    func listenToLatestGame(groupId: String,
                            onChange: @escaping (GuessGame?) -> Void) -> ListenerRegistration {
        db.collection("guess_games")
            .whereField("groupId", isEqualTo: groupId)
            .order(by: "createdAt", descending: true)
            .limit(to: 1)
            .addSnapshotListener { snapshot, error in
                if let error {
                    print("GuessGameRepository listen error: \(error.localizedDescription)")
                    return
                }
                guard let document = snapshot?.documents.first else {
                    onChange(nil)
                    return
                }
                onChange(GuessGame.from(documentID: document.documentID, data: document.data()))
            }
    }

    // MARK: - Round lifecycle

    /// Drawer starts a round: picks a word+hint pair, writes the game doc AND the
    /// drawer-sealed secret. Returns the gameId + chosen pair (the drawer may show the
    /// word immediately). `forcedWord` exists for deterministic tests only.
    @discardableResult
    func createRound(groupId: String,
                     memberIds: [String],
                     drawerId: String,
                     drawerName: String,
                     forcedWord: WordBank.Pair? = nil) async throws -> (gameId: String, pair: WordBank.Pair) {
        let pair = forcedWord ?? WordBank.randomPair()
        let gameId = UUID().uuidString
        let normalizedWord = GuessNormalizer.normalize(pair.word)
        let letterBank = LetterBankBuilder.build(word: normalizedWord, gameId: gameId)

        let gameFields: [String: Any] = [
            "groupId": groupId,
            "status": GuessGame.Status.drawing.rawValue,
            "drawerId": drawerId,
            "drawerName": drawerName,
            "winnerId": "",
            "winnerName": "",
            "gaveUpUsers": [String](),
            "memberIds": memberIds,
            "wordHint": pair.category,
            "letterBank": letterBank,
            "wordLength": normalizedWord.count,
            "strokeData": "",
            "attempts": [[String: Any]](),
            "result": "",
            "revealedWord": "",
            "guesserId": "",
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
        ]

        let gameRef = db.collection("guess_games").document(gameId)
        let secretRef = gameRef.collection("secret").document("word")

        // Game doc + sealed secret written together so a round never exists wordless.
        let batch = db.batch()
        batch.setData(gameFields, forDocument: gameRef)
        batch.setData(["word": normalizedWord], forDocument: secretRef)
        try await batch.commit()
        return (gameId, pair)
    }

    /// Drawer publishes the doodle → status GUESSING (worker fans out pushes).
    func publishDrawing(gameId: String, strokeData: String) async throws {
        try await db.collection("guess_games").document(gameId).updateData([
            "strokeData": strokeData,
            "status": GuessGame.Status.guessing.rawValue,
            "updatedAt": FieldValue.serverTimestamp(),
        ])
    }

    /// Drawer shuffles: secret word AND hint/category update as one atomic batch, so
    /// the visible hint can never belong to a previous word.
    @discardableResult
    func shuffleWord(gameId: String, forcedPair: WordBank.Pair? = nil) async throws -> WordBank.Pair {
        let pair = forcedPair ?? WordBank.randomPair()
        let normalizedWord = GuessNormalizer.normalize(pair.word)
        let letterBank = LetterBankBuilder.build(word: normalizedWord, gameId: gameId)

        let gameRef = db.collection("guess_games").document(gameId)
        let secretRef = gameRef.collection("secret").document("word")

        let batch = db.batch()
        batch.updateData(["word": normalizedWord], forDocument: secretRef)
        batch.updateData([
            "wordHint": pair.category,
            "letterBank": letterBank,
            "wordLength": normalizedWord.count,
            "updatedAt": FieldValue.serverTimestamp(),
        ], forDocument: gameRef)
        try await batch.commit()
        return pair
    }

    /// Drawer-only secret read (enforced by backend rules) — used for word recall
    /// and the game canvas header. Returns nil when rules deny the read.
    func fetchSecretWord(gameId: String) async throws -> String? {
        let snapshot = try await db.collection("guess_games")
            .document(gameId)
            .collection("secret")
            .document("word")
            .getDocument()
        guard snapshot.exists else { return nil }
        return snapshot.data()?["word"] as? String
    }

    // MARK: - Judging (worker-authoritative)

    func checkGuess(gameId: String, userId: String, userName: String, guess: String) async throws -> JudgeResult {
        try await judge.judge(action: "checkGuess",
                              gameId: gameId,
                              userId: userId,
                              userName: userName,
                              guess: GuessNormalizer.normalize(guess))
    }

    func giveUp(gameId: String, userId: String, userName: String) async throws -> JudgeResult {
        try await judge.judge(action: "giveUp",
                              gameId: gameId,
                              userId: userId,
                              userName: userName,
                              guess: "")
    }

    // MARK: - Takeover

    /// After TURN_TAKEOVER_MS with no drawing progress, an eligible member claims the
    /// pen. Timestamps stay server-authoritative via serverTimestamp().
    func takeOverDrawing(gameId: String, userId: String, userName: String) async throws {
        try await db.collection("guess_games").document(gameId).updateData([
            "drawerId": userId,
            "drawerName": userName,
            "updatedAt": FieldValue.serverTimestamp(),
        ])
    }
}
