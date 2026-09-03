import XCTest
@testable import Alarmify

/// 開発者メニューが組み立てる push payload が、push 受信時と同じ `AlarmRequest(userInfo:)` で読めることのテスト
final class DebugPushPayloadTests: XCTestCase {
    func testScheduleUserInfoIsParsedAsScheduleRequest() {
        // fire_at は秒精度の ISO 8601 のため、比較対象も秒に丸める
        let fireDate = Date(timeIntervalSince1970: 1_788_418_800)

        let request = AlarmRequest(userInfo: DebugPushPayload.scheduleUserInfo(fireDate: fireDate))

        XCTAssertEqual(request?.id, DebugPushPayload.alarmID)
        XCTAssertEqual(request?.action, .schedule)
        XCTAssertEqual(request?.fireDate, fireDate)
        XCTAssertEqual(request?.title, DebugPushPayload.title)
    }

    func testScheduleUserInfoTruncatesFractionalSeconds() {
        let fireDate = Date(timeIntervalSince1970: 1_788_418_800.75)

        let request = AlarmRequest(userInfo: DebugPushPayload.scheduleUserInfo(fireDate: fireDate))

        XCTAssertEqual(request?.fireDate, Date(timeIntervalSince1970: 1_788_418_800))
    }

    func testCancelUserInfoIsParsedAsCancelRequestForTheSameID() {
        let request = AlarmRequest(userInfo: DebugPushPayload.cancelUserInfo())

        XCTAssertEqual(request?.id, DebugPushPayload.alarmID)
        XCTAssertEqual(request?.action, .cancel)
        XCTAssertNil(request?.fireDate)
    }

    func testScheduleUserInfoHasTheSameShapeAsSchedulePayload() throws {
        let userInfo = DebugPushPayload.scheduleUserInfo(fireDate: .now)

        let aps = try XCTUnwrap(userInfo["aps"] as? [String: Any])
        XCTAssertEqual(aps["mutable-content"] as? Int, 1)
        let alarm = try XCTUnwrap(userInfo[AlarmRequest.payloadKey] as? [String: Any])
        XCTAssertEqual(Set(alarm.keys), ["id", "action", "fire_at", "title"])
    }
}
