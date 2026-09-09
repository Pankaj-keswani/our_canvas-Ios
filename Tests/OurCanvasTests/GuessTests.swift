import XCTest
import Foundation
@testable import OurCanvas

// MARK: - Guess fixtures

private func makeGameFixture(status: String = "GUESSING",
                             drawerId: String = "drawer-1",
                             guesserId: String? = nil,
                             winnerId: String? = nil,
                             winnerName: String? = nil,
                             result: String? = nil,
                             gaveUpUsers: [String] = [],
                             updatedAt: Date? = nil) -> [String: Any] {
    var fixture: [String: Any] = [
        "groupId": "group-1",
        "status": status,
        "drawerId": drawerId,
        "drawerName": "Riya",
        "winnerId": winnerId ?? "",
        "winnerName": winnerName ?? "",
        "gaveUpUsers": gaveUpUsers,
        "memberIds": ["drawer-1", "guesser-1", "guesser-2"],
        "wordHint": "Animal",
        "letterBank": ["C", "A", "T", "X", "E", "O"],
        "wordLength": 3,
        "strokeData": "{}",
        "attempts": [
            ["userId": "guesser-1", "userName": "Sam", "guess": "cat"],
            ["userId": "guesser-2", "userName": "Ash", "guess": "dog"],
        ],
        "result": result ?? "",
        "revealedWord": "",
        "guesserId": guesserId ?? "",
        "futureAndroidField": ["anything": true],
    ]
    if let updatedAt {
        fixture["updatedAt"] = updatedAt
    }
    return fixture
}

// MARK: - 1/2. Model decoding (new + legacy)

final class GuessModelDecodingTests: XCTestCase {
    func testDecodesNewMultiplayerGame() {
        let game = GuessGame.from(documentID: "game-1", data: makeGameFixture())
        XCTAssertEqual(game.id, "game-1")
        XCTAssertEqual(game.groupId, "group-1")
        XCTAssertEqual(game.status, .guessing)
        XCTAssertEqual(game.drawerId, "drawer-1")
        XCTAssertEqual(game.drawerName, "Riya")
        XCTAssertEqual(game.wordLength, 3)
        XCTAssertEqual(game.letterBank.count, 6)
        XCTAssertEqual(game.attempts.count, 2)
        XCTAssertEqual(game.attempts[0].guess, "cat")
        XCTAssertFalse(game.isLegacy)
        XCTAssertNil(game.result)
    }

    func testDecodesLegacyOneVsOneGame() {
        let game = GuessGame.from(documentID: "game-old", data: makeGameFixture(guesserId: "guesser-1"))
        XCTAssertTrue(game.isLegacy, "non-blank guesserId marks legacy 1v1 games")
        XCTAssertEqual(game.guesserId, "guesser-1")
    }

    func testUnknownStatusDefaultsToDrawing() {
        let game = GuessGame.from(documentID: "g", data: makeGameFixture(status: "SOMETHING_NEW"))
        XCTAssertEqual(game.status, .drawing, "unknown future statuses must not crash")
    }

    func testFinishedGameWithResultAndWinner() {
        let game = GuessGame.from(documentID: "g", data: makeGameFixture(
            status: "FINISHED", winnerId: "guesser-2", winnerName: "Ash", result: "CORRECT"))
        XCTAssertEqual(game.status, .finished)
        XCTAssertEqual(game.result, .correct)
        XCTAssertEqual(game.winnerName, "Ash")
    }
}

// MARK: - 3. Card state machine

final class GuessCardStateTests: XCTestCase {
    func testNoGameShowsStartCard() {
        XCTAssertEqual(GuessCardState.derive(game: nil, uid: "u1", localRevealedWord: nil), .noGame)
    }

    func testDrawerNeverEntersGuessUI() {
        let game = GuessGame.from(documentID: "g", data: makeGameFixture())
        let state = GuessCardState.derive(game: game, uid: "drawer-1", localRevealedWord: nil)
        XCTAssertEqual(state, .drawingAsDrawer(game: game, word: nil))

        // Even in GUESSING the drawer must not reach the guessing card.
        if case .guessing = state { XCTFail("drawer must never see the guessing card") }
    }

    func testNonDrawerWaitsWhileDrawing() {
        let game = GuessGame.from(documentID: "g", data: makeGameFixture(status: "DRAWING"))
        let state = GuessCardState.derive(game: game, uid: "guesser-1", localRevealedWord: nil)
        XCTAssertEqual(state, .drawingWaiting(game: game))
    }

    func testNonDrawerGuessesWhenGuessing() {
        let game = GuessGame.from(documentID: "g", data: makeGameFixture(status: "GUESSING"))
        let state = GuessCardState.derive(game: game, uid: "guesser-1", localRevealedWord: nil)
        XCTAssertEqual(state, .guessing(game: game, revealedLocally: false))
    }

    func testRevealedUserSpectates() {
        let game = GuessGame.from(documentID: "g", data: makeGameFixture(status: "GUESSING"))
        let state = GuessCardState.derive(game: game, uid: "guesser-1", localRevealedWord: "cat")
        XCTAssertEqual(state, .gaveUpSpectate(game: game, revealedWord: "cat"))
    }

    func testServerGaveUpFlagSpectatesWithoutWord() {
        let game = GuessGame.from(documentID: "g", data: makeGameFixture(status: "GUESSING", gaveUpUsers: ["guesser-1"]))
        let state = GuessCardState.derive(game: game, uid: "guesser-1", localRevealedWord: nil)
        XCTAssertEqual(state, .gaveUpSpectate(game: game, revealedWord: ""))
    }

    func testLegacyStates() {
        let legacy = GuessGame.from(documentID: "g", data: makeGameFixture(guesserId: "guesser-1"))
        XCTAssertEqual(GuessCardState.derive(game: legacy, uid: "guesser-1", localRevealedWord: nil),
                       .legacyGuessing(game: legacy))
        XCTAssertEqual(GuessCardState.derive(game: legacy, uid: "guesser-2", localRevealedWord: nil),
                       .legacySpectator(game: legacy))
    }

    func testFinishedState() {
        let game = GuessGame.from(documentID: "g", data: makeGameFixture(status: "FINISHED"))
        XCTAssertEqual(GuessCardState.derive(game: game, uid: "guesser-1", localRevealedWord: nil),
                       .finished(game: game))
    }
}

// MARK: - 5/6. Letter bank interaction model

final class LetterBankModelTests: XCTestCase {
    func testSelectionFillsSlotsWithoutRemovingFromPool() {
        var model = LetterBankModel(bank: ["C", "A", "T", "X"], maxSlots: 3)
        model.select(index: 0)
        model.select(index: 1)
        XCTAssertEqual(model.currentAnswer, "CA")
        XCTAssertEqual(model.availableIndices.count, 2, "letters are only marked used, never removed")
        XCTAssertFalse(model.isFull)
    }

    func testCannotSelectBeyondWordLength() {
        var model = LetterBankModel(bank: ["C", "A", "T", "X"], maxSlots: 3)
        model.select(index: 0)
        model.select(index: 1)
        model.select(index: 2)
        model.select(index: 3)
        XCTAssertTrue(model.isFull)
        XCTAssertEqual(model.currentAnswer, "CAT", "fourth selection ignored")
    }

    func testCannotReuseSameTileTwice() {
        var model = LetterBankModel(bank: ["A", "B"], maxSlots: 3)
        model.select(index: 0)
        model.select(index: 0)
        XCTAssertEqual(model.currentAnswer, "A")
    }

    func testDeleteReturnsMostRecentLetterToBank() {
        var model = LetterBankModel(bank: ["C", "A", "T"], maxSlots: 3)
        model.select(index: 0)
        model.select(index: 2)
        XCTAssertEqual(model.currentAnswer, "CT")
        XCTAssertTrue(model.canDelete)

        let returned = model.deleteLast()
        XCTAssertEqual(returned, 2, "delete returns the most recently selected tile")
        XCTAssertFalse(model.isSelected(2), "tile is available in the bank again")
        XCTAssertEqual(model.currentAnswer, "C")
    }

    func testDeleteDisabledWhenEmpty() {
        var model = LetterBankModel(bank: ["C"], maxSlots: 2)
        XCTAssertFalse(model.canDelete)
        XCTAssertNil(model.deleteLast())
    }

    func testResetClearsAllSlots() {
        var model = LetterBankModel(bank: ["C", "A"], maxSlots: 2)
        model.select(index: 0)
        model.select(index: 1)
        model.reset()
        XCTAssertEqual(model.currentAnswer, "")
        XCTAssertEqual(model.availableIndices.count, 2)
    }
}

// MARK: - 7. Reveal local key format

final class GuessRevealKeyTests: XCTestCase {
    func testRevealKeyUsesAndroidFormat() {
        let suiteName = "tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = UserScopedStore(uid: "user-9", defaults: defaults)
        store.setRevealedWord("cat", gameId: "game-7")
        XCTAssertEqual(store.revealedWord(gameId: "game-7"), "cat")
        XCTAssertNil(store.revealedWord(gameId: "game-8"), "reveals are per-game")

        // Raw key embeds Android's {gameId}_{uid} suffix under guess_reveals.
        XCTAssertEqual(defaults.string(forKey: "user.user-9.guessReveals.game-7_user-9"), "cat")
    }
}

// MARK: - 8/14/15. FinishedCard ordering + winner-next + all-gave-up

final class GuessNextDrawerTests: XCTestCase {
    func testWinnerDrawsNext() {
        let game = GuessGame.from(documentID: "g", data: makeGameFixture(
            status: "FINISHED", winnerId: "guesser-2", winnerName: "Ash", result: "CORRECT"))
        XCTAssertEqual(game.nextDrawerId, "guesser-2")
        XCTAssertEqual(game.nextDrawerName, "Ash")
    }

    func testAllGaveUpKeepsDrawerAsNext() {
        let game = GuessGame.from(documentID: "g", data: makeGameFixture(
            status: "FINISHED", result: "GAVE_UP", gaveUpUsers: ["guesser-1", "guesser-2"]))
        XCTAssertEqual(game.nextDrawerId, "drawer-1", "drawer keeps the pen when nobody cracked it")
        XCTAssertEqual(game.nextDrawerName, "Riya")
    }

    func testRecentAttemptsCappedAtEight() {
        var fixture = makeGameFixture()
        fixture["attempts"] = (0..<20).map { ["userId": "u\($0)", "guess": "g\($0)"] }
        let game = GuessGame.from(documentID: "g", data: fixture)
        XCTAssertEqual(game.recentAttempts.count, 8)
        XCTAssertEqual(game.recentAttempts.last?.guess, "g19")
    }
}

// MARK: - 9. 24-hour takeover

final class GuessTakeoverTests: XCTestCase {
    func testTakeoverBlockedBefore24Hours() {
        let game = GuessGame.from(documentID: "g", data: makeGameFixture(status: "DRAWING"))
        XCTAssertFalse(GuessTakeover.canTakeOver(game: game, uid: "guesser-1", now: Date()))
    }

    func testTakeoverAllowedAfter24Hours() {
        let stale = Date().addingTimeInterval(-GuessTakeover.takeoverInterval - 60)
        let game = GuessGame.from(documentID: "g", data: makeGameFixture(status: "DRAWING", updatedAt: stale))
        XCTAssertTrue(GuessTakeover.canTakeOver(game: game, uid: "guesser-1", now: Date()))
    }

    func testDrawerCannotTakeOverOwnTurn() {
        let stale = Date().addingTimeInterval(-GuessTakeover.takeoverInterval - 60)
        let game = GuessGame.from(documentID: "g", data: makeGameFixture(status: "DRAWING", updatedAt: stale))
        XCTAssertFalse(GuessTakeover.canTakeOver(game: game, uid: "drawer-1", now: Date()))
    }

    func testTakeoverOnlyInDrawingPhase() {
        let stale = Date().addingTimeInterval(-GuessTakeover.takeoverInterval - 60)
        let guessing = GuessGame.from(documentID: "g", data: makeGameFixture(status: "GUESSING", updatedAt: stale))
        XCTAssertFalse(GuessTakeover.canTakeOver(game: guessing, uid: "guesser-1", now: Date()))
    }
}

// MARK: - 10/11. Worker contract

final class WorkerContractTests: XCTestCase {
    func testCheckGuessRequestPayload() {
        let payload = WorkerJudgeClient.requestPayload(action: "checkGuess",
                                                       gameId: "game-1",
                                                       userId: "u1",
                                                       userName: "Sam",
                                                       guess: "cat")
        XCTAssertEqual(payload["action"] as? String, "checkGuess")
        XCTAssertEqual(payload["gameId"] as? String, "game-1")
        XCTAssertEqual(payload["userId"] as? String, "u1")
        XCTAssertEqual(payload["userName"] as? String, "Sam")
        XCTAssertEqual(payload["guess"] as? String, "cat")
        XCTAssertEqual(Set(payload.keys), ["action", "gameId", "userId", "userName", "guess"])
    }

    func testGiveUpRequestPayload() {
        let payload = WorkerJudgeClient.requestPayload(action: "giveUp",
                                                       gameId: "game-1",
                                                       userId: "u1",
                                                       userName: "Sam",
                                                       guess: "")
        XCTAssertEqual(payload["action"] as? String, "giveUp")
        XCTAssertEqual(payload["guess"] as? String, "")
    }

    func testParsesFullWorkerResponse() throws {
        let json = """
        {"correct":true,"word":"cat","gaveUp":false,"roundOver":true,"lostRace":false,"winnerName":"Sam"}
        """
        let result = try XCTUnwrap(WorkerJudgeClient.parseResponse(Data(json.utf8)))
        XCTAssertTrue(result.correct)
        XCTAssertEqual(result.word, "cat")
        XCTAssertFalse(result.gaveUp)
        XCTAssertTrue(result.roundOver)
        XCTAssertFalse(result.lostRace)
        XCTAssertEqual(result.winnerName, "Sam")
    }

    func testParsesLostRaceResponseWithMissingFields() throws {
        let json = """
        {"correct":false,"lostRace":true,"winnerName":"Ash"}
        """
        let result = try XCTUnwrap(WorkerJudgeClient.parseResponse(Data(json.utf8)))
        XCTAssertFalse(result.correct)
        XCTAssertTrue(result.lostRace)
        XCTAssertEqual(result.winnerName, "Ash")
        XCTAssertFalse(result.roundOver, "missing fields default safely")
        XCTAssertNil(result.word, "the secret is never exposed to a losing guesser")
    }

    func testGarbageResponseReturnsNil() {
        XCTAssertNil(WorkerJudgeClient.parseResponse(Data("not json".utf8)))
        XCTAssertNil(WorkerJudgeClient.parseResponse(Data("[]".utf8)))
    }

    func testUnconfiguredWorkerConfigIsNotConfigured() {
        let config = WorkerConfig(baseURL: nil, apiKey: "")
        XCTAssertFalse(config.isConfigured)
    }

    // MARK: Judge error mapping (shared worker, post cf320597)

    func testConflictMapsToRoundEndedCopy() {
        let error = WorkerJudgeClient.error(forStatusCode: 409)
        XCTAssertEqual(error.message, "This round already ended")
        XCTAssertNotEqual(error, AppError.network, "a wrong-phase 409 must not blame the connection")
    }

    func testOtherStatusesKeepGenericConnectionError() {
        // Matches Android: genuine members no longer hit 403 after the worker's
        // live-membership fallback, so remaining failures stay generic.
        for status in [400, 403, 404, 500, -1] {
            XCTAssertEqual(WorkerJudgeClient.error(forStatusCode: status), AppError.network,
                           "status \(status) should keep the generic connection error")
        }
    }

    func testJudgeErrorCopySurvivesViewModelRewrap() {
        // GuessGameViewModel surfaces errors via AppError.from(error).message —
        // typed AppErrors thrown by the judge client must survive that rewrap.
        let conflict = AppError.from(WorkerJudgeClient.error(forStatusCode: 409))
        XCTAssertEqual(conflict.message, "This round already ended")

        XCTAssertEqual(AppError.from(AppError.network), AppError.network)
        XCTAssertEqual(AppError.from(AppError.underlying("Guess judging isn't configured for this build yet. Coming soon!")).message,
                       "Guess judging isn't configured for this build yet. Coming soon!")
    }
}

// MARK: - Idempotent judge replays (shared worker cf4717ce)

/// On slow networks the judge can commit server-side while the HTTP response is
/// lost; the worker now replays the recorded outcome with 200 instead of a 409
/// error storm. These tests lock the client-side interpretation of each replay.
final class JudgeReplayTests: XCTestCase {
    private func parse(_ json: String) -> JudgeResult {
        guard let result = WorkerJudgeClient.parseResponse(Data(json.utf8)) else {
            XCTFail("replay fixture must parse")
            return JudgeResult()
        }
        return result
    }

    func testWinnerRetryReplaysCorrectWithWord() {
        let result = parse(#"{"correct":true,"word":"cat","roundOver":true}"#)
        XCTAssertEqual(GuessOutcomeAction.action(for: result), .correct)
        XCTAssertEqual(result.word, "cat")
    }

    func testLoserRetryReplaysLostRaceWithPublicWord() {
        let result = parse(#"{"correct":false,"lostRace":true,"winnerName":"Ash","word":"cat","roundOver":true}"#)
        XCTAssertEqual(GuessOutcomeAction.action(for: result), .lostRace(winnerName: "Ash"))
        XCTAssertEqual(result.word, "cat", "the word is public once the round is finished")
    }

    func testGaveUpFinishReplayMapsToRevealed() {
        let result = parse(#"{"correct":false,"gaveUp":true,"roundOver":true,"word":"cat"}"#)
        XCTAssertEqual(GuessOutcomeAction.action(for: result), .revealed(word: "cat"))
    }

    func testRevealRetryWhileStillGuessingMapsToRevealed() {
        let result = parse(#"{"correct":false,"gaveUp":true,"roundOver":false,"word":"cat"}"#)
        XCTAssertEqual(GuessOutcomeAction.action(for: result), .revealed(word: "cat"))
    }

    func testEmptyReplayWordNeverCountsAsReveal() {
        let result = parse(#"{"correct":false,"gaveUp":true,"roundOver":false,"word":""}"#)
        XCTAssertEqual(GuessOutcomeAction.action(for: result), .none,
                       "persisting an empty reveal would strand the user on a blank spectate card")
    }

    func testRevealCardWordComesFromLocalStoreNotGameDoc() {
        var fixture = makeGameFixture(status: "GUESSING")
        fixture["revealedWord"] = "cat" // doc field only becomes authoritative at FINISH
        let game = GuessGame.from(documentID: "g", data: fixture)

        // Local reveal store populated (worker response persisted) → word shows.
        XCTAssertEqual(GuessCardState.derive(game: game, uid: "guesser-1", localRevealedWord: "cat"),
                       .gaveUpSpectate(game: game, revealedWord: "cat"))

        // No local reveal → guessing card, even if the doc field were set early.
        XCTAssertEqual(GuessCardState.derive(game: game, uid: "guesser-1", localRevealedWord: nil),
                       .guessing(game: game, revealedLocally: false))
    }
}

// MARK: - 12/13/14. Judge outcome mapping

final class GuessOutcomeTests: XCTestCase {
    func testCorrectGuess() {
        let result = JudgeResult(correct: true, word: "cat", gaveUp: false, roundOver: true)
        XCTAssertEqual(GuessOutcomeAction.action(for: result), .correct)
    }

    func testLostRaceIncludesWinnerName() {
        let result = JudgeResult(lostRace: true, winnerName: "Ash")
        XCTAssertEqual(GuessOutcomeAction.action(for: result), .lostRace(winnerName: "Ash"))
    }

    func testWrongGuessContinuesRound() {
        let result = JudgeResult()
        XCTAssertEqual(GuessOutcomeAction.action(for: result), .wrong)
        XCTAssertFalse(result.roundOver)
    }

    func testGiveUpRevealsWordOnlyToThisUser() {
        let result = JudgeResult(word: "cat", gaveUp: true)
        XCTAssertEqual(GuessOutcomeAction.action(for: result), .revealed(word: "cat"))
    }

    func testGiveUpWithoutWordIsSilent() {
        let result = JudgeResult(gaveUp: true)
        XCTAssertEqual(GuessOutcomeAction.action(for: result), .none)
    }
}

// MARK: - 16. Word/hint pair + letter bank construction

final class WordBankTests: XCTestCase {
    func testWordHintPairIntegrity() {
        for _ in 0..<25 {
            let pair = WordBank.randomPair()
            XCTAssertFalse(pair.word.isEmpty)
            XCTAssertFalse(pair.category.isEmpty)
            XCTAssertTrue(WordBank.pairs.contains(pair))
        }
    }

    func testLetterBankContainsWordLettersPlusDecoys() {
        let bank = LetterBankBuilder.build(word: "cat", gameId: "game-1")
        XCTAssertEqual(bank.count, 3 + LetterBankBuilder.decoyPool.count)
        for letter in "cat" {
            XCTAssertTrue(bank.contains(String(letter)), "bank must contain every letter of the word")
        }
    }

    func testLetterBankDeterministicPerGameId() {
        let a = LetterBankBuilder.build(word: "cat", gameId: "game-1")
        let b = LetterBankBuilder.build(word: "cat", gameId: "game-1")
        let c = LetterBankBuilder.build(word: "cat", gameId: "game-2")
        XCTAssertEqual(a, b, "same gameId → identical bank on every client")
        XCTAssertNotEqual(a, c, "different gameId → different shuffle")
    }

    func testNormalizerMatchesWorkerSemantics() {
        XCTAssertEqual(GuessNormalizer.normalize("  CaT! "), "cat")
        XCTAssertEqual(GuessNormalizer.normalize("ÉLAN"), "lan")
        XCTAssertEqual(GuessNormalizer.normalize(""), "")
    }
}

// MARK: - 17. Stroke envelope compatibility (Android fixture parity)

final class StrokeEnvelopeCompatibilityTests: XCTestCase {
    func testEncodedEnvelopeUsesAndroidFieldNames() throws {
        let stroke = Stroke(points: [CGPoint(x: 10, y: 20), CGPoint(x: 30, y: 40)],
                            color: 0xFFFF0000, width: 9, brush: .marker)
        let json = StrokeSerializer.encode(strokes: [stroke],
                                           background: .default,
                                           canvasSize: CGSize(width: 1080, height: 1080))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(FieldCast.int(root["cw"]), 1080)
        XCTAssertEqual(FieldCast.int(root["ch"]), 1080)
        let strokes = try XCTUnwrap(root["strokes"] as? [[String: Any]])
        XCTAssertEqual(strokes[0].keys.count, 4)
        XCTAssertEqual(Set(strokes[0].keys), ["c", "w", "b", "p"])
        XCTAssertEqual(FieldCast.int(strokes[0]["b"]), 2, "MARKER serializes as Android ordinal 2")
    }

    func testDecodesAndroidProducedStrokeFixture() {
        // Format copied from Android SketchCanvasView.exportStrokeData().
        let androidJson = """
        {"cw":1080,"ch":1080,"strokes":[{"c":-65536,"w":12.0,"b":0,"p":[[100.0,150.0],[200.0,250.0]]},{"c":-1,"w":40.0,"b":4,"p":[[10.0,10.0]]}]}
        """
        let parsed = StrokeSerializer.decode(androidJson)
        XCTAssertEqual(parsed.canvasWidth, 1080)
        XCTAssertEqual(parsed.strokes.count, 2)
        XCTAssertEqual(parsed.strokes[0].color, 0xFFFF0000, "-65536 (Android red) decodes as ARGB int")
        XCTAssertEqual(parsed.strokes[0].points.count, 2)
        XCTAssertEqual(parsed.strokes[1].brush, .rainbow, "ordinal 4 = RAINBOW in current production order")
    }
}
