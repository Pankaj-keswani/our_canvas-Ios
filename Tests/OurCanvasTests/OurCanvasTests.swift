import XCTest
@testable import OurCanvas

final class SerializationTests: XCTestCase {
    func testStrokeSerialization() throws {
        let point = PointRecord(x: 10.5, y: 20.1)
        let stroke = StrokeRecord(points: [point], color: 16711680, strokeWidth: 12.0, brushType: .basic)
        
        let json = StrokeSerializer.exportStrokeData(records: [stroke], width: 1080, height: 1080)
        XCTAssertTrue(json.contains("\"cw\":1080.0") || json.contains("\"cw\":1080"))
        XCTAssertTrue(json.contains("\"c\":16711680"))
        XCTAssertTrue(json.contains("[10.5,20.1]"))
        
        let parsed = StrokeSerializer.importStrokeData(jsonStr: json)
        XCTAssertEqual(parsed.records.count, 1)
        XCTAssertEqual(parsed.records[0].points.first?.x, 10.5)
    }
}

final class ModelTests: XCTestCase {
    func testGroupModelDecoding() throws {
        let json = """
        {
            "id": "test_id",
            "groupId": "test_id",
            "groupName": "My Circle",
            "groupType": "custom",
            "createdBy": "uid_123",
            "inviteCode": "ABCDEF",
            "memberIds": ["uid_123"]
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let group = try decoder.decode(Group.self, from: json)
        
        XCTAssertEqual(group.groupName, "My Circle")
        XCTAssertEqual(group.memberIds.count, 1)
    }
}
