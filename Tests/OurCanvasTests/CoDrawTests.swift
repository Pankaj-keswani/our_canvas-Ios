import XCTest
import Foundation
@testable import OurCanvas

// MARK: - Co-Draw fixtures

private func participantFixture(displayName: String = "Sam",
                                isActive: Bool = true,
                                lastSeenAgo: TimeInterval? = 10) -> [String: Any] {
    var fields: [String: Any] = [
        "displayName": displayName,
        "isActive": isActive,
    ]
    if let lastSeenAgo {
        fields["lastSeenAt"] = Date(timeIntervalSinceNow: -lastSeenAgo)
    }
    return fields
}

private func sessionFixture(status: String? = "ACTIVE",
                            participants: [String: [String: Any]]) -> [String: Any] {
    var data: [String: Any] = [
        "groupId": "group-1",
        "participants": participants,
        "activeParticipantCount": participants.count,
        "createdBy": "u1",
    ]
    if let status {
        data["status"] = status
    }
    return data
}

// MARK: - 18. Session model decoding

final class CoDrawSessionModelTests: XCTestCase {
    func testDecodesActiveSession() {
        let data = sessionFixture(participants: [
            "u1": participantFixture(),
            "u2": participantFixture(displayName: "Ash", lastSeenAgo: 30),
        ])
        let session = CoDrawSession.from(documentID: "group-1", data: data)
        XCTAssertEqual(session.id, "group-1")
        XCTAssertEqual(session.status, .active)
        XCTAssertEqual(session.participants.count, 2)
        XCTAssertEqual(session.participants["u1"]?.displayName, "Sam")
        XCTAssertTrue(session.isJoinable)
    }

    func testDecodesEndedSession() {
        let session = CoDrawSession.from(documentID: "g", data: sessionFixture(status: "ENDED", participants: [:]))
        XCTAssertEqual(session.status, .ended)
    }

    func testMissingStatusFieldDecodesAsNil() {
        let session = CoDrawSession.from(documentID: "g", data: sessionFixture(status: nil, participants: ["u1": participantFixture()]))
        XCTAssertNil(session.status)
    }

    func testDecodesLiveStrokeEvent() {
        let data: [String: Any] = [
            "userId": "u2",
            "op": "STROKE_OR_UNKNOWN",
            "seq": 3,
            "isComplete": false,
            "canvasW": 1080.0,
            "canvasH": 1080.0,
            "c": -65536,
            "w": 12.0,
            "b": 0,
            "points": [[10.0, 20.0], [30.0, 40.0]],
        ]
        let event = CoDrawLiveStroke.from(documentID: "stroke-1", data: data)
        XCTAssertEqual(event.userId, "u2")
        XCTAssertEqual(event.kind, .stroke, "unknown ops fall back to stroke kind")
        XCTAssertEqual(event.sequence, 3)
        XCTAssertFalse(event.isComplete)
        XCTAssertEqual(event.points.count, 2)
        XCTAssertEqual(event.brush, .basic)
        XCTAssertEqual(event.color, 0xFFFF0000)
    }

    func testDecodesOperationEvents() {
        let undo = CoDrawLiveStroke.from(documentID: "op-1", data: ["userId": "u2", "op": "DELETE_STROKE", "isComplete": true])
        XCTAssertEqual(undo.kind, .undo)
        let clear = CoDrawLiveStroke.from(documentID: "op-2", data: ["userId": "u2", "op": "CLEAR", "isComplete": true])
        XCTAssertEqual(clear.kind, .clear)
    }
}

// MARK: - 19/27/28. Lifecycle + recovery rules

final class CoDrawLifecycleTests: XCTestCase {
    func testMissingSessionRequiresNew() {
        XCTAssertTrue(CoDrawLifecycle.requiresNewSession(nil))
    }

    func testEndedSessionRequiresNew() {
        let session = CoDrawSession.from(documentID: "g", data: sessionFixture(status: "ENDED", participants: ["u1": participantFixture()]))
        XCTAssertTrue(CoDrawLifecycle.requiresNewSession(session))
    }

    func testMissingStatusRequiresNew() {
        let session = CoDrawSession.from(documentID: "g", data: sessionFixture(status: nil, participants: ["u1": participantFixture()]))
        XCTAssertTrue(CoDrawLifecycle.requiresNewSession(session))
    }

    func testZeroActiveParticipantsRequiresNew() {
        let session = CoDrawSession.from(documentID: "g", data: sessionFixture(participants: [
            "u1": participantFixture(isActive: false),
        ]))
        XCTAssertTrue(CoDrawLifecycle.requiresNewSession(session))
    }

    func testHealthySessionIsReused() {
        let session = CoDrawSession.from(documentID: "g", data: sessionFixture(participants: [
            "u1": participantFixture(),
        ]))
        XCTAssertFalse(CoDrawLifecycle.requiresNewSession(session))
    }

    func testLiveActiveCountExcludesStaleParticipants() {
        let session = CoDrawSession.from(documentID: "g", data: sessionFixture(participants: [
            "u1": participantFixture(),
            "stale": participantFixture(displayName: "Ghost", lastSeenAgo: CoDrawLifecycle.staleThreshold + 60),
            "inactive": participantFixture(displayName: "Left", isActive: false, lastSeenAgo: 5),
        ]))
        XCTAssertEqual(session.liveActiveCount, 1)
    }
}

// MARK: - 20. Stale detection boundaries

final class CoDrawStalenessTests: XCTestCase {
    func testFreshParticipantIsActive() {
        let participant = CoDrawSession.Participant.from(data: participantFixture(lastSeenAgo: CoDrawLifecycle.staleThreshold - 1))
        XCTAssertTrue(CoDrawLifecycle.isActive(participant, now: Date()))
    }

    func testParticipantStaleAfterFiveMinutes() {
        let participant = CoDrawSession.Participant.from(data: participantFixture(lastSeenAgo: CoDrawLifecycle.staleThreshold + 1))
        XCTAssertFalse(CoDrawLifecycle.isActive(participant, now: Date()))
    }

    func testMissingLastSeenIsInactive() {
        let participant = CoDrawSession.Participant.from(data: participantFixture(lastSeenAgo: nil))
        XCTAssertFalse(CoDrawLifecycle.isActive(participant, now: Date()))
    }

    func testInactivelyFlaggedParticipantIsInactive() {
        let participant = CoDrawSession.Participant.from(data: participantFixture(isActive: false, lastSeenAgo: 1))
        XCTAssertFalse(CoDrawLifecycle.isActive(participant, now: Date()))
    }
}

// MARK: - 21. Heartbeat cadence constants

final class CoDrawHeartbeatTests: XCTestCase {
    func testHeartbeatEvery45Seconds() {
        XCTAssertEqual(CoDrawLifecycle.heartbeatInterval, 45, "Android presence heartbeat cadence")
    }

    func testStaleWindowIsFiveMinutes() {
        XCTAssertEqual(CoDrawLifecycle.staleThreshold, 5 * 60)
    }
}

// MARK: - 22. Sequence ordering

final class CoDrawSequenceTests: XCTestCase {
    func testMonotonicSequencesAreOrdered() {
        XCTAssertTrue(CoDrawLifecycle.isOrdered(sequences: [1, 2, 3, 10]))
    }

    func testDuplicateOrReorderedSequencesFail() {
        XCTAssertFalse(CoDrawLifecycle.isOrdered(sequences: [1, 1, 2]))
        XCTAssertFalse(CoDrawLifecycle.isOrdered(sequences: [3, 2, 4]))
        XCTAssertTrue(CoDrawLifecycle.isOrdered(sequences: [1]))
        XCTAssertTrue(CoDrawLifecycle.isOrdered(sequences: []))
    }
}

// MARK: - 23. Incomplete stroke accumulation

final class RemoteStrokeAccumulatorTests: XCTestCase {
    func testAccumulatesProgressiveBatches() {
        var accumulator = RemoteStrokeAccumulator(userId: "u2",
                                                  color: 0xFF000000,
                                                  width: 12,
                                                  brush: .basic)
        accumulator.append(points: [CGPoint(x: 10, y: 20)], sequence: 1,
                           sourceCanvas: CGSize(width: 1080, height: 1080),
                           localCanvasSize: CGSize(width: 1080, height: 1080))
        accumulator.append(points: [CGPoint(x: 30, y: 40)], sequence: 2,
                           sourceCanvas: CGSize(width: 1080, height: 1080),
                           localCanvasSize: CGSize(width: 1080, height: 1080))
        XCTAssertEqual(accumulator.stroke.points.count, 2)
        XCTAssertEqual(accumulator.lastSequence, 2)
        XCTAssertEqual(accumulator.stroke.ownerId, "u2")
    }

    func testIgnoresDuplicateAndStaleSequences() {
        var accumulator = RemoteStrokeAccumulator(userId: "u2", color: 0, width: 8, brush: .basic)
        accumulator.append(points: [CGPoint(x: 1, y: 1)], sequence: 2,
                           sourceCanvas: CGSize(width: 1080, height: 1080),
                           localCanvasSize: CGSize(width: 1080, height: 1080))
        accumulator.append(points: [CGPoint(x: 2, y: 2)], sequence: 2, // duplicate
                           sourceCanvas: CGSize(width: 1080, height: 1080),
                           localCanvasSize: CGSize(width: 1080, height: 1080))
        accumulator.append(points: [CGPoint(x: 3, y: 3)], sequence: 1, // stale
                           sourceCanvas: CGSize(width: 1080, height: 1080),
                           localCanvasSize: CGSize(width: 1080, height: 1080))
        XCTAssertEqual(accumulator.stroke.points.count, 1, "out-of-order batches must not double-render")
    }

    func testFullSnapshotReplayIsIdempotent() {
        var accumulator = RemoteStrokeAccumulator(userId: "u2", color: 0, width: 8, brush: .basic)
        let allPoints = [CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 2), CGPoint(x: 3, y: 3)]
        // Snapshot listener re-delivers the full accumulated document twice.
        for _ in 0..<2 {
            accumulator.append(points: allPoints, sequence: 1,
                               sourceCanvas: CGSize(width: 1080, height: 1080),
                               localCanvasSize: CGSize(width: 1080, height: 1080))
            accumulator.append(points: allPoints, sequence: 2,
                               sourceCanvas: CGSize(width: 1080, height: 1080),
                               localCanvasSize: CGSize(width: 1080, height: 1080))
        }
        XCTAssertEqual(accumulator.stroke.points.count, 6, "re-delivered snapshots append exactly once per sequence")
    }
}

// MARK: - 24. Cross-device canvas scaling

final class CoDrawScalingTests: XCTestCase {
    func testUniformScalePreservesRelativePositions() {
        let source = CGSize(width: 1080, height: 1080)
        let target = CGSize(width: 390, height: 390)
        let center = CoDrawLifecycle.scalePoint(CGPoint(x: 540, y: 540), from: source, to: target)
        XCTAssertEqual(center.x, 195, accuracy: 0.5)
        XCTAssertEqual(center.y, 195, accuracy: 0.5)

        let corner = CoDrawLifecycle.scalePoint(CGPoint(x: 1080, y: 0), from: source, to: target)
        XCTAssertEqual(corner.x, 390, accuracy: 0.5)
        XCTAssertEqual(corner.y, 0, accuracy: 0.5)
    }

    func testSmallPhoneToLargePhone() {
        let source = CGSize(width: 320, height: 320)
        let target = CGSize(width: 430, height: 430)
        let point = CoDrawLifecycle.scalePoint(CGPoint(x: 160, y: 80), from: source, to: target)
        XCTAssertEqual(point.x, 215, accuracy: 0.5)
        XCTAssertEqual(point.y, 107.5, accuracy: 0.5)
    }

    func testNonSquareSourceKeepsAspectViaUniformScale() {
        let source = CGSize(width: 1000, height: 500)
        let target = CGSize(width: 400, height: 400)
        // Uniform scale = 0.4 → content letterboxes horizontally.
        let point = CoDrawLifecycle.scalePoint(CGPoint(x: 500, y: 250), from: source, to: target)
        XCTAssertEqual(point.x, 200 + 0, accuracy: 0.5)
        XCTAssertEqual(point.y, 100 + 100, accuracy: 0.5, "vertical centering offset applied")
    }
}

// MARK: - 25/26. Undo/clear operations on the engine

@MainActor
final class CoDrawEngineOperationsTests: XCTestCase {
    func testRemoteUndoRemovesOnlyThatUsersLatestStroke() {
        let engine = DrawingEngine()
        engine.appendRemoteStroke(Stroke(points: [CGPoint(x: 1, y: 1)], color: 1, width: 5, brush: .basic, ownerId: "u2"))
        engine.appendRemoteStroke(Stroke(points: [CGPoint(x: 2, y: 2)], color: 1, width: 5, brush: .basic, ownerId: "u3"))
        engine.appendRemoteStroke(Stroke(points: [CGPoint(x: 3, y: 3)], color: 1, width: 5, brush: .basic, ownerId: "u2"))
        XCTAssertEqual(engine.strokes.count, 3)

        engine.removeLastStroke(ownerId: "u2")
        XCTAssertEqual(engine.strokes.count, 2)
        XCTAssertEqual(engine.strokes[0].ownerId, "u2", "u2's FIRST stroke survives")
        XCTAssertEqual(engine.strokes[1].ownerId, "u3")
    }

    func testRemoteUndoWithNoOwnerRemovesLatest() {
        let engine = DrawingEngine()
        engine.appendRemoteStroke(Stroke(points: [CGPoint(x: 1, y: 1)], color: 1, width: 5, brush: .basic, ownerId: "u2"))
        engine.appendRemoteStroke(Stroke(points: [CGPoint(x: 2, y: 2)], color: 1, width: 5, brush: .basic, ownerId: nil))
        engine.removeLastStroke(ownerId: nil)
        XCTAssertEqual(engine.strokes.count, 1)
    }

    func testRemoteClearRemovesEverything() {
        let engine = DrawingEngine()
        engine.appendRemoteStroke(Stroke(points: [CGPoint(x: 1, y: 1)], color: 1, width: 5, brush: .basic, ownerId: "u2"))
        engine.beginStroke(at: CGPoint(x: 5, y: 5))
        engine.extendStroke(to: CGPoint(x: 50, y: 50))
        engine.endStroke()
        XCTAssertEqual(engine.strokes.count, 2)

        engine.applyRemoteClear()
        XCTAssertEqual(engine.strokes.count, 0)
    }

    func testRemoteStrokesDoNotEnterLocalUndoHistory() {
        let engine = DrawingEngine()
        engine.appendRemoteStroke(Stroke(points: [CGPoint(x: 1, y: 1)], color: 1, width: 5, brush: .basic, ownerId: "u2"))
        XCTAssertFalse(engine.canUndo, "remote strokes are not locally undoable")
        engine.undo()
        XCTAssertEqual(engine.strokes.count, 1, "undo with empty stack changes nothing")
    }
}
