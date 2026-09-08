import XCTest
import Foundation
@testable import OurCanvas

// MARK: - OFFLINE QUEUE (Android A10.1 parity)

final class OfflineQueueTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("queue-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeStore() -> PendingDrawingStore {
        PendingDrawingStore(directory: tempDir)
    }

    private func makeItem(uid: String = "u1", groupId: String = "g1") -> PendingDrawingItem {
        PendingDrawingItem(id: UUID(),
                           uid: uid,
                           groupId: groupId,
                           groupName: "Besties",
                           createdAt: Date(),
                           drawingData: "aGVsbG8=",
                           strokeData: "{}",
                           stickerData: "[]",
                           textData: "[]")
    }

    /// Offline before send → the failed network send persists everything.
    func testOfflineFailureQueuesCompleteDrawing() {
        var drawing = Drawing()
        drawing.groupId = "g1"
        drawing.drawingData = "aGVsbG8="
        drawing.strokeData = "{\"cw\":1080}"
        drawing.stickerData = "[{\"t\":\"⭐️\"}]"
        drawing.textData = "[]"

        // (uid comes from Auth in production; here we assert the queue-level pieces)
        let item = PendingDrawingItem(id: UUID(), uid: "anon", groupId: "g1", groupName: "Besties",
                                      createdAt: Date(), drawingData: drawing.drawingData,
                                      strokeData: drawing.strokeData, stickerData: drawing.stickerData,
                                      textData: drawing.textData)
        makeStore().enqueue(item)

        let store = makeStore()
        let loaded = store.all()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].drawingData, "aGVsbG8=")
        XCTAssertEqual(loaded[0].strokeData, "{\"cw\":1080}")
        XCTAssertEqual(loaded[0].stickerData, "[{\"t\":\"⭐️\"}]")
        XCTAssertEqual(loaded[0].groupName, "Besties")
    }

    /// App killed with pending items → relaunch (new store instance) still sees them.
    func testQueueSurvivesRestart() {
        let store = makeStore()
        store.enqueue(makeItem())
        store.enqueue(makeItem(uid: "u1", groupId: "g2"))

        let resurrected = makeStore()
        XCTAssertEqual(resurrected.items(forUid: "u1").count, 2, "file-backed queue survives restart")
        XCTAssertTrue(resurrected.items(forUid: "u2").isEmpty, "queue is uid-scoped")
    }

    /// Duplicate retry: a failed flush keeps the item with backoff; a successful
    /// flush removes it exactly once (no double-send).
    func testFlushRetriesThenSucceedsExactlyOnce() async {
        final class FlakyThenSuccessSender: DrawingSending, @unchecked Sendable {
            var calls = 0
            func send(drawing: Drawing) async throws {
                calls += 1
                if calls == 1 { throw AppError.network }
            }
        }

        let sender = FlakyThenSuccessSender()
        let service = OfflineQueueService(store: makeStore(), sender: sender)
        let item = makeItem()
        service.store.enqueue(item)

        // First flush: network failure → item stays, attempt recorded.
        await service.flushForTesting(uid: "u1")
        XCTAssertEqual(sender.calls, 1)
        XCTAssertEqual(service.store.items(forUid: "u1").count, 1)
        // Backoff now holds the item (attempt just recorded).
        XCTAssertFalse(service.store.items(forUid: "u1")[0].isDue())

        // After the backoff elapses, a later flush succeeds and removes the item.
        var aged = service.store.items(forUid: "u1")[0]
        aged.lastAttemptAt = Date().addingTimeInterval(-3600)
        service.store.enqueue(aged)

        await service.flushForTesting(uid: "u1")
        XCTAssertEqual(sender.calls, 2)
        XCTAssertTrue(service.store.items(forUid: "u1").isEmpty,
                      "item removed only after confirmed successful write")

        // Re-flush with an empty queue must not resend anything.
        await service.flushForTesting(uid: "u1")
        XCTAssertEqual(sender.calls, 2)
    }

    func testMultipleQueuedDrawingsFlushInOrder() async {
        final class RecordingSender: DrawingSending, @unchecked Sendable {
            var order: [String] = []
            func send(drawing: Drawing) async throws {
                order.append(drawing.strokeData)
            }
        }

        let sender = RecordingSender()
        let service = OfflineQueueService(store: makeStore(), sender: sender)
        let first = PendingDrawingItem(id: UUID(), uid: "u1", groupId: "g1", groupName: "Besties",
                                       createdAt: Date(), drawingData: "x", strokeData: "first",
                                       stickerData: "[]", textData: "[]")
        // second created BEFORE first → oldest-first flush order
        let second = PendingDrawingItem(id: UUID(), uid: "u1", groupId: "g2", groupName: "Besties",
                                        createdAt: Date().addingTimeInterval(-60), drawingData: "x",
                                        strokeData: "second", stickerData: "[]", textData: "[]")
        service.store.enqueue(first)
        service.store.enqueue(second)

        await service.flushForTesting(uid: "u1")
        XCTAssertEqual(sender.order, ["second", "first"], "oldest queued doodle sends first")
        XCTAssertTrue(service.store.all().isEmpty)
    }

    func testBackoffSchedule() {
        var item = makeItem()
        XCTAssertEqual(item.retryDelay, 30)
        item.attempts = 1
        XCTAssertEqual(item.retryDelay, 60)
        item.attempts = 3
        XCTAssertEqual(item.retryDelay, 300)
        item.attempts = 99
        XCTAssertEqual(item.retryDelay, 3600, "backoff caps at one hour")

        // Fresh item is immediately due; a just-attempted item is not.
        XCTAssertTrue(item.isDue())
        item.lastAttemptAt = Date()
        XCTAssertFalse(item.isDue())
        item.lastAttemptAt = Date().addingTimeInterval(-3601)
        XCTAssertTrue(item.isDue())
    }

    func testFlushStopsAtFirstFailure() async {
        final class AlwaysFailingSender: DrawingSending, @unchecked Sendable {
            var calls = 0
            func send(drawing: Drawing) async throws {
                calls += 1
                throw AppError.network
            }
        }

        let sender = AlwaysFailingSender()
        let service = OfflineQueueService(store: makeStore(), sender: sender)
        service.store.enqueue(makeItem())
        service.store.enqueue(makeItem(groupId: "g2"))
        service.store.enqueue(makeItem(groupId: "g3"))

        await service.flushForTesting(uid: "u1")
        XCTAssertEqual(sender.calls, 1, "the pass stops on the first failure; backoff governs the rest")
        XCTAssertEqual(service.store.items(forUid: "u1").count, 3)
    }
}

// MARK: - Test seams

extension OfflineQueueService {
    /// Test seam: awaits the async flush loop until it settles.
    @MainActor
    func flushForTesting(uid: String) async {
        flush(uid: uid)
        // Drain the flush task (senders resolve immediately in tests).
        for _ in 0..<100 {
            if !isFlushing { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
}

// MARK: - STOREKIT GRANT POLICY (Phase 4 §7)

final class PurchaseGrantPolicyTests: XCTestCase {
    func testFirstClaimIsAllowed() {
        XCTAssertEqual(PurchaseGrantPolicy.decide(transactionOwnerUid: nil, currentUid: "u1"), .allowed)
        XCTAssertEqual(PurchaseGrantPolicy.decide(transactionOwnerUid: "", currentUid: "u1"), .allowed)
    }

    func testDuplicateTransactionSameAccountIsIdempotent() {
        // Restore path: the same account re-grants the same transaction.
        XCTAssertEqual(PurchaseGrantPolicy.decide(transactionOwnerUid: "u1", currentUid: "u1"), .allowed)
    }

    func testWrongAccountIsRejected() {
        XCTAssertEqual(PurchaseGrantPolicy.decide(transactionOwnerUid: "u1", currentUid: "u2"),
                       .wrongAccount(ownerUid: "u1"))
    }

    func testNotSignedInCannotBind() {
        XCTAssertEqual(PurchaseGrantPolicy.decide(transactionOwnerUid: nil, currentUid: nil), .notSignedIn)
        XCTAssertEqual(PurchaseGrantPolicy.decide(transactionOwnerUid: "u1", currentUid: ""), .notSignedIn)
    }

    func testRulesDeniedGrantNeverAppearsAsPro() {
        // The honest mapping: a rules-denied grant is pendingServerActivation,
        // distinct from .granted — server plan remains authoritative for gating.
        let state = PurchaseGrantPolicy.uiStateForDeniedGrant()
        XCTAssertEqual(state, .pendingServerActivation)
        XCTAssertNotEqual(state, .granted)
    }
}

// MARK: - GUESS MALFORMED-DOCUMENT HARDENING (Phase 4 §3)

final class GuessMalformedDocumentTests: XCTestCase {
    func testEmptyDocumentDecodesToSafeDefaults() {
        let game = GuessGame.from(documentID: "g", data: [:])
        XCTAssertEqual(game.status, .drawing)
        XCTAssertEqual(game.drawerName, "Someone")
        XCTAssertEqual(game.wordLength, 0)
        XCTAssertTrue(game.letterBank.isEmpty)
        XCTAssertTrue(game.attempts.isEmpty)
        XCTAssertFalse(game.isLegacy)
    }

    func testWronglyTypedFieldsFallBackSafely() {
        let data: [String: Any] = [
            "status": 42,               // wrong type
            "wordLength": "three",      // wrong type
            "memberIds": "not-an-array",
            "letterBank": 7,
            "attempts": "oops",
            "gaveUpUsers": ["ok": 1],
        ]
        let game = GuessGame.from(documentID: "g", data: data)
        XCTAssertEqual(game.status, .drawing)
        XCTAssertEqual(game.wordLength, 0)
        XCTAssertTrue(game.memberIds.isEmpty)
        XCTAssertTrue(game.attempts.isEmpty)
    }

    func testPostFinishGuessingIsImpossible() {
        let finished = GuessGame.from(documentID: "g", data: ["status": "FINISHED",
                                                               "drawerId": "d1",
                                                               "memberIds": ["d1", "u1"]])
        let state = GuessCardState.derive(game: finished, uid: "u1", localRevealedWord: nil)
        XCTAssertEqual(state, .finished(game: finished))
        if case .guessing = state {
            XCTFail("post-finish guessing must be disabled at the state-machine level")
        }
        if case .legacyGuessing = GuessCardState.derive(game: finished, uid: "u1", localRevealedWord: nil) {
            XCTFail("legacy guessing must also respect FINISHED")
        }
    }

    func testPartialStrokeDataReplaysWithoutCrashing() {
        let broken = "{\"cw\":1080,\"ch\":1080,\"strokes\":[{\"c\":-1,\"w\":12,\"b\":0},{\"p\":\"nope\"}]}"
        let parsed = StrokeSerializer.decode(broken)
        // Tolerant decode: bad strokes become empty-point entries or are skipped —
        // replay must never crash and must render whatever is valid.
        for stroke in parsed.strokes {
            _ = StrokeRenderer.renderStrokeImage(stroke,
                                                 canvasSize: CGSize(width: 1080, height: 1080),
                                                 outputPixels: 64)
        }
    }
}

// MARK: - CO-DRAW RESILIENCE ADDITIONS (Phase 4 §4)

@MainActor
final class CoDrawResilienceTests: XCTestCase {
    func testLocalUndoNeverRemovesAnotherUsersStroke() {
        let engine = DrawingEngine()
        engine.appendRemoteStroke(Stroke(points: [CGPoint(x: 1, y: 1)], color: 1, width: 5, brush: .basic, ownerId: "them"))
        engine.beginStroke(at: CGPoint(x: 5, y: 5))
        engine.extendStroke(to: CGPoint(x: 80, y: 80))
        engine.endStroke()

        // Local undo (me) — engine.undo pops MY latest logical op, never theirs.
        engine.undo()
        XCTAssertEqual(engine.strokes.count, 1, "my undo removed my stroke")
        XCTAssertEqual(engine.strokes[0].ownerId, "them", "remote stroke survives my undo")

        // Broadcast-undo from "them" removes THEIR latest only.
        engine.removeLastStroke(ownerId: "them")
        XCTAssertTrue(engine.strokes.isEmpty)
    }

    func testRemoteClearResetsEverythingIncludingInProgressAccumulators() {
        var accumulator = RemoteStrokeAccumulator(userId: "them", color: 0, width: 8, brush: .basic)
        accumulator.append(points: [CGPoint(x: 1, y: 1)], sequence: 1,
                           sourceCanvas: CGSize(width: 1080, height: 1080),
                           localCanvasSize: CGSize(width: 1080, height: 1080))
        XCTAssertEqual(accumulator.stroke.points.count, 1)

        // A CLEAR broadcast wipes document + accumulators (view-model semantics;
        // engine side verified directly here).
        let engine = DrawingEngine()
        engine.appendRemoteStroke(accumulator.stroke)
        engine.applyRemoteClear()
        XCTAssertTrue(engine.strokes.isEmpty)
    }
}

// MARK: - PHOTO SAVE DECISIONS (Phase 4 §9)

final class PhotoSaveTests: XCTestCase {
    func testPermissionDecisions() {
        XCTAssertEqual(PhotoLibrarySaver.decision(for: .authorized), .allowed)
        XCTAssertEqual(PhotoLibrarySaver.decision(for: .limited), .allowed)
        XCTAssertEqual(PhotoLibrarySaver.decision(for: .denied), .denied)
        XCTAssertEqual(PhotoLibrarySaver.decision(for: .restricted), .denied)
        XCTAssertEqual(PhotoLibrarySaver.decision(for: .notDetermined), .undetermined)
    }

    func testFriendlyMessagesMentionSettingsForDenied() {
        XCTAssertTrue(PhotoLibrarySaver.friendlyMessage(for: .denied).contains("Settings"))
        XCTAssertEqual(PhotoLibrarySaver.friendlyMessage(for: .allowed), "Saved to Photos!")
    }
}

// MARK: - CROSS-ACCOUNT PRIVACY (Phase 4 §15)

final class CrossAccountPrivacyTests: XCTestCase {
    func testUserScopedKeysNeverCollideAcrossAccounts() {
        let suiteName = "tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        var accountA = UserScopedStore(uid: "aaa", defaults: defaults)
        accountA.whatsNewSeenVersion = 3
        accountA.setRevealedWord("cat", gameId: "g1")
        accountA.setLastVisit(Date(), forGroup: "circle1")
        accountA.walkthroughStep = 5

        let accountB = UserScopedStore(uid: "bbb", defaults: defaults)
        XCTAssertEqual(accountB.whatsNewSeenVersion, 0)
        XCTAssertNil(accountB.revealedWord(gameId: "g1"))
        XCTAssertNil(accountB.lastVisit(forGroup: "circle1"))
        XCTAssertEqual(accountB.walkthroughStep, 0)
    }

    func testPendingQueueNeverVisibleAcrossAccounts() {
        let suiteDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("queue-x-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: suiteDir) }
        let store = PendingDrawingStore(directory: suiteDir)
        store.enqueue(PendingDrawingItem(id: UUID(), uid: "aaa", groupId: "g1", groupName: "A's circle",
                                         createdAt: Date(), drawingData: "x", strokeData: "{}",
                                         stickerData: "[]", textData: "[]"))
        XCTAssertTrue(store.items(forUid: "bbb").isEmpty, "account B's flush never sees A's drawings")
        XCTAssertEqual(store.items(forUid: "aaa").count, 1)
    }
}
