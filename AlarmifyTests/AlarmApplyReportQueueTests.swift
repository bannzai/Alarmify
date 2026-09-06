import XCTest
@testable import Alarmify

/// バックエンドへ未送信の適用結果を App Group に積むキューのテスト
final class AlarmApplyReportQueueTests: XCTestCase {
    private let id = UUID(uuidString: "3B0E0C6E-9F1B-4C0A-9E7D-1F2A3B4C5D6E")!
    private let now = Date(timeIntervalSince1970: 1_788_418_800)
    private var queue: AlarmApplyReportQueue!

    override func setUp() {
        super.setUp()
        let suiteName = "AlarmApplyReportQueueTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        queue = AlarmApplyReportQueue(userDefaults: userDefaults)
    }

    func testEnqueueKeepsOnlyTheLatestReportPerAlarmAndAction() {
        queue.enqueue(AlarmApplyReport(alarmID: id, action: .schedule, result: .failed, error: "limit", occurredAt: now))
        queue.enqueue(AlarmApplyReport(alarmID: id, action: .schedule, result: .applied, error: nil, occurredAt: now.addingTimeInterval(1)))
        queue.enqueue(AlarmApplyReport(alarmID: id, action: .cancel, result: .applied, error: nil, occurredAt: now.addingTimeInterval(2)))

        XCTAssertEqual(queue.pending, [
            AlarmApplyReport(alarmID: id, action: .schedule, result: .applied, error: nil, occurredAt: now.addingTimeInterval(1)),
            AlarmApplyReport(alarmID: id, action: .cancel, result: .applied, error: nil, occurredAt: now.addingTimeInterval(2)),
        ])
    }

    func testRemoveDropsTheSentReportOnly() {
        let sent = AlarmApplyReport(alarmID: id, action: .schedule, result: .applied, error: nil, occurredAt: now)
        let other = AlarmApplyReport(alarmID: UUID(), action: .schedule, result: .applied, error: nil, occurredAt: now)
        queue.enqueue(sent)
        queue.enqueue(other)

        queue.remove(sent)
        queue.remove(sent)

        XCTAssertEqual(queue.pending, [other])
    }

    func testRemovingTheLastReportEmptiesTheQueue() {
        let report = AlarmApplyReport(alarmID: id, action: .schedule, result: .applied, error: nil, occurredAt: now)
        queue.enqueue(report)

        queue.remove(report)

        XCTAssertTrue(queue.pending.isEmpty)
    }
}
