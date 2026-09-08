import XCTest
@testable import OurCanvas

final class SerializationTests: XCTestCase {
    func testStrokeSerializationRoundTrip() throws {
        let stroke = Stroke(points: [CGPoint(x: 10.5, y: 20.1), CGPoint(x: 30.0, y: 40.0)],
                            color: 0xFFFF0000,
                            width: 12,
                            brush: .basic)

        let json = StrokeSerializer.encode(strokes: [stroke],
                                           background: .default,
                                           canvasSize: CGSize(width: 1080, height: 1080))
        XCTAssertTrue(json.contains("\"cw\""))
        XCTAssertTrue(json.contains("\"strokes\""))

        let parsed = StrokeSerializer.decode(json)
        XCTAssertEqual(parsed.canvasWidth, 1080)
        XCTAssertEqual(parsed.strokes.count, 1)
        XCTAssertEqual(parsed.strokes[0].points.first?.x ?? 0, 10.5, accuracy: 0.01)
        XCTAssertEqual(parsed.strokes[0].brush, .basic)
        XCTAssertEqual(parsed.strokes[0].color, 0xFFFF0000)
    }
}

final class ModelTests: XCTestCase {
    func testGroupModelInitialization() {
        let group = Group(
            id: "test_id",
            groupId: "test_id",
            groupName: "My Circle",
            groupType: "custom",
            createdBy: "uid_123",
            createdAt: 123456789,
            inviteCode: "ABCDEF",
            memberIds: ["uid_123"]
        )

        XCTAssertEqual(group.groupName, "My Circle")
        XCTAssertEqual(group.memberIds.count, 1)
        XCTAssertEqual(group.inviteCode, "ABCDEF")
    }
}
