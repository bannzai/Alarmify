import XCTest

@testable import Alarmify

/// ホームの「次に鳴るアラーム」の日付の表記 (nextAlarmDay) と、履歴の送信元の prefix の引き当て (prefix(tokenID:)) のテスト。
/// 日付は暦日で判定するため、時刻の差ではなく日付の境界 (深夜の跨ぎ) で今日 / 明日が変わる
final class HomeNextAlarmTests: XCTestCase {
    /// 判定に使う暦。端末のタイムゾーン設定に依存しないよう UTC に固定する
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    /// 2026-09-10 23:50 UTC (日付の境界の 10 分前)
    private let now = Date(timeIntervalSince1970: 1_789_084_200)

    /// 同じ暦日なら今日
    func testSameDayIsToday() {
        XCTAssertEqual(nextAlarmDay(fireDate: now.addingTimeInterval(5 * 60), now: now, calendar: calendar), .today)
    }

    /// 時刻の差が短くても日付を跨げば明日
    func testAfterMidnightIsTomorrow() {
        XCTAssertEqual(nextAlarmDay(fireDate: now.addingTimeInterval(20 * 60), now: now, calendar: calendar), .tomorrow)
    }

    /// 明日の終わりまでは明日
    func testEndOfTomorrowIsTomorrow() {
        XCTAssertEqual(nextAlarmDay(fireDate: now.addingTimeInterval(24 * 60 * 60 + 9 * 60), now: now, calendar: calendar), .tomorrow)
    }

    /// 明後日以降は月日で出す
    func testDayAfterTomorrowIsLater() {
        XCTAssertEqual(nextAlarmDay(fireDate: now.addingTimeInterval(2 * 24 * 60 * 60), now: now, calendar: calendar), .later)
    }

    /// 履歴の tokenID に対応する prefix を返し、一覧に無い (失効済み) id は nil
    func testTokenPrefixLookup() {
        let tokens = [
            APIToken(id: "tok-1", name: "default", prefix: "alm_9f2c", createdAt: now, lastUsedAt: nil),
            APIToken(id: "tok-2", name: "default", prefix: "alm_c31a", createdAt: now, lastUsedAt: nil),
        ]
        XCTAssertEqual(tokens.prefix(tokenID: "tok-2"), "alm_c31a")
        XCTAssertNil(tokens.prefix(tokenID: "tok-revoked"))
    }
}
