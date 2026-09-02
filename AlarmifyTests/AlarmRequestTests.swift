import XCTest
@testable import Alarmify

/// push payload から AlarmRequest を組み立てる境界のテスト
final class AlarmRequestTests: XCTestCase {
    private let id = UUID(uuidString: "3B0E0C6E-9F1B-4C0A-9E7D-1F2A3B4C5D6E")!

    func testScheduleRequestIsParsedFromUserInfo() {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["content-available": 1],
            "alarm": ["id": id.uuidString, "action": "schedule", "fire_at": "2026-09-03T07:00:00Z", "title": "Deploy finished"],
        ]

        let request = AlarmRequest(userInfo: userInfo)

        XCTAssertEqual(request?.id, id)
        XCTAssertEqual(request?.action, .schedule)
        XCTAssertEqual(request?.fireDate, Date(timeIntervalSince1970: 1_788_418_800))
        XCTAssertEqual(request?.title, "Deploy finished")
    }

    func testCancelRequestDoesNotRequireFireDate() {
        let request = AlarmRequest(payload: ["id": id.uuidString, "action": "cancel"])

        XCTAssertEqual(request?.action, .cancel)
        XCTAssertNil(request?.fireDate)
    }

    func testScheduleRequestWithoutFireDateIsRejected() {
        XCTAssertNil(AlarmRequest(payload: ["id": id.uuidString, "action": "schedule"]))
    }

    func testInvalidFireDateIsRejected() {
        XCTAssertNil(AlarmRequest(payload: ["id": id.uuidString, "action": "schedule", "fire_at": "tomorrow"]))
    }

    func testInvalidIDOrActionIsRejected() {
        XCTAssertNil(AlarmRequest(payload: ["id": "not-a-uuid", "action": "schedule", "fire_at": "2026-09-03T07:00:00Z"]))
        XCTAssertNil(AlarmRequest(payload: ["id": id.uuidString, "action": "snooze", "fire_at": "2026-09-03T07:00:00Z"]))
    }

    func testUserInfoWithoutAlarmKeyIsNil() {
        XCTAssertNil(AlarmRequest(userInfo: ["aps": ["alert": "hello"]]))
    }
}
