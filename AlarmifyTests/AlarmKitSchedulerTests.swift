import XCTest
@testable import Alarmify

/// `AlarmRequest` → `AlarmKitScheduler.apply` の冪等性と、件数上限対策の整理ロジックのテスト。
/// AlarmKit 本体には触れず、メモリ上の偽の登録先 (`FakeAlarmStore`) に差し替えて検証する
final class AlarmKitSchedulerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_788_418_800)
    private let id = UUID(uuidString: "3B0E0C6E-9F1B-4C0A-9E7D-1F2A3B4C5D6E")!
    private var store: FakeAlarmStore!
    private var userDefaults: UserDefaults!
    /// テストは 1 プロセスで順に動き、競合する書き手がいないためロックしない
    private let noLock = SharedStoreLock(fileURL: nil)

    override func setUp() {
        super.setUp()
        store = FakeAlarmStore()
        // App Group の実体に書かず、テストごとに空の suite を使う
        let suiteName = "AlarmKitSchedulerTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    private var dependencies: AlarmSchedulerDependencies {
        let store = store!
        let now = now
        return AlarmSchedulerDependencies(
            registeredAlarms: { try store.registeredAlarms() },
            schedule: { id, fireDate, title in try await store.schedule(id: id, fireDate: fireDate, title: title) },
            cancel: { id in store.cancel(id: id) },
            userDefaults: userDefaults,
            storeLock: noLock,
            now: { now }
        )
    }

    private func scheduleRequest(fireDate: Date, title: String = "Deploy finished") -> AlarmRequest {
        AlarmRequest(payload: [
            "id": id.uuidString,
            "action": "schedule",
            "fire_at": ISO8601DateFormatter().string(from: fireDate),
            "title": title,
        ])!
    }

    func testApplyingTheSameScheduleTwiceKeepsOneAlarm() async throws {
        let request = scheduleRequest(fireDate: now.addingTimeInterval(600))

        try await AlarmKitScheduler.apply(request, dependencies: dependencies)
        try await AlarmKitScheduler.apply(request, dependencies: dependencies)

        XCTAssertEqual(store.alarms.count, 1)
        XCTAssertEqual(store.alarms[id]?.fireDate, request.fireDate)
        XCTAssertEqual(store.scheduleCount, 2, "再送でも登録し直す (取消 → 登録) が、結果は 1 件のまま")
    }

    func testReschedulingTheSameIDReplacesTheFireDateAndTitle() async throws {
        try await AlarmKitScheduler.apply(scheduleRequest(fireDate: now.addingTimeInterval(600), title: "first"), dependencies: dependencies)
        try await AlarmKitScheduler.apply(scheduleRequest(fireDate: now.addingTimeInterval(1200), title: "second"), dependencies: dependencies)

        XCTAssertEqual(store.alarms.count, 1)
        XCTAssertEqual(store.alarms[id]?.fireDate, now.addingTimeInterval(1200))
        XCTAssertEqual(store.alarms[id]?.title, "second")
        XCTAssertEqual(AlarmTitleStore(userDefaults: userDefaults, lock: noLock).title(id: id), "second")
    }

    func testCancelRemovesTheAlarmAndItsTitle() async throws {
        try await AlarmKitScheduler.apply(scheduleRequest(fireDate: now.addingTimeInterval(600)), dependencies: dependencies)

        try await AlarmKitScheduler.apply(AlarmRequest(payload: ["id": id.uuidString, "action": "cancel"])!, dependencies: dependencies)

        XCTAssertTrue(store.alarms.isEmpty)
        XCTAssertNil(AlarmTitleStore(userDefaults: userDefaults, lock: noLock).title(id: id))
    }

    func testSchedulingCancelsPastAlarmsButKeepsFutureAndAlertingOnes() async throws {
        let past = UUID()
        let alerting = UUID()
        let future = UUID()
        let titles = AlarmTitleStore(userDefaults: userDefaults, lock: noLock)
        store.alarms[past] = FakeAlarmStore.Entry(fireDate: now.addingTimeInterval(-60), title: "past", isAlerting: false)
        store.alarms[alerting] = FakeAlarmStore.Entry(fireDate: now.addingTimeInterval(-60), title: "alerting", isAlerting: true)
        store.alarms[future] = FakeAlarmStore.Entry(fireDate: now.addingTimeInterval(60), title: "future", isAlerting: false)
        titles.save(title: "past", id: past)

        try await AlarmKitScheduler.apply(scheduleRequest(fireDate: now.addingTimeInterval(600)), dependencies: dependencies)

        XCTAssertEqual(Set(store.alarms.keys), [alerting, future, id])
        XCTAssertNil(titles.title(id: past), "整理したアラームのタイトルも消す")
    }

    func testExpiredAlarmIDsIgnoresRelativeAlarms() {
        let relative = UUID()
        store.alarms[relative] = FakeAlarmStore.Entry(fireDate: nil, title: "relative", isAlerting: false)
        store.alarms[id] = FakeAlarmStore.Entry(fireDate: now.addingTimeInterval(-1), title: "past", isAlerting: false)

        let expired = AlarmKitScheduler.expiredAlarmIDs(alarms: Array(store.alarms.map { FakeAlarmStore.Registered(id: $0.key, entry: $0.value) }), now: now)

        XCTAssertEqual(expired, [id])
    }

    func testSchedulingStillWorksWhenTheAlarmListCannotBeRead() async throws {
        store.alarmsError = FakeAlarmStore.Failure.unavailable

        try await AlarmKitScheduler.apply(scheduleRequest(fireDate: now.addingTimeInterval(600)), dependencies: dependencies)

        XCTAssertEqual(store.alarms.count, 1)
    }

    func testApplyEnqueuesAnAppliedReport() async throws {
        try await AlarmKitScheduler.apply(scheduleRequest(fireDate: now.addingTimeInterval(600)), dependencies: dependencies)

        let pending = AlarmApplyReportQueue(userDefaults: userDefaults, lock: noLock).pending
        XCTAssertEqual(pending, [AlarmApplyReport(alarmID: id, action: .schedule, result: .applied, error: nil, occurredAt: now, fireAt: now.addingTimeInterval(600))])
    }

    func testFailedReportTruncatesTheErrorToTheServerLimit() async {
        store.scheduleError = FakeAlarmStore.Failure.tooLongDescription

        try? await AlarmKitScheduler.apply(scheduleRequest(fireDate: now.addingTimeInterval(600)), dependencies: dependencies)

        let pending = AlarmApplyReportQueue(userDefaults: userDefaults, lock: noLock).pending
        XCTAssertEqual(pending.first?.error?.count, AlarmApplyReport.maxErrorLength)
        XCTAssertEqual(pending.first?.error, String(FakeAlarmStore.Failure.tooLongDescription.localizedDescription.prefix(AlarmApplyReport.maxErrorLength)))
    }

    func testApplyEnqueuesAFailedReportAndRethrows() async {
        store.scheduleError = FakeAlarmStore.Failure.limitReached

        do {
            try await AlarmKitScheduler.apply(scheduleRequest(fireDate: now.addingTimeInterval(600)), dependencies: dependencies)
            XCTFail("Expected the scheduling error to be rethrown")
        } catch {
            XCTAssertEqual(error as? FakeAlarmStore.Failure, .limitReached)
        }

        let pending = AlarmApplyReportQueue(userDefaults: userDefaults, lock: noLock).pending
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.result, .failed)
        XCTAssertEqual(pending.first?.error, FakeAlarmStore.Failure.limitReached.localizedDescription)
        XCTAssertTrue(store.alarms.isEmpty)
    }
}

/// メモリ上の AlarmKit の代わり。登録・取消の呼び出しを記録する
final class FakeAlarmStore: @unchecked Sendable {
    struct Entry: Equatable {
        var fireDate: Date?
        var title: String
        var isAlerting: Bool
    }

    /// `RegisteredAlarm` として整理ロジックへ渡す形
    struct Registered: RegisteredAlarm {
        let id: UUID
        let entry: Entry

        var fixedFireDate: Date? { entry.fireDate }
        var isAlerting: Bool { entry.isAlerting }
    }

    enum Failure: Error, Equatable, LocalizedError {
        case unavailable
        case limitReached
        /// サーバーが受け付ける長さ (500 文字) を超える説明を持つエラー
        case tooLongDescription

        var errorDescription: String? {
            switch self {
            case .unavailable, .limitReached:
                return nil
            case .tooLongDescription:
                return String(repeating: "x", count: AlarmApplyReport.maxErrorLength + 100)
            }
        }
    }

    var alarms: [UUID: Entry] = [:]
    var alarmsError: Failure?
    var scheduleError: Failure?
    private(set) var scheduleCount = 0

    func registeredAlarms() throws -> [any RegisteredAlarm] {
        if let alarmsError { throw alarmsError }
        return alarms.map { Registered(id: $0.key, entry: $0.value) }
    }

    func schedule(id: UUID, fireDate: Date, title: String) async throws {
        scheduleCount += 1
        if let scheduleError { throw scheduleError }
        alarms[id] = Entry(fireDate: fireDate, title: title, isAlerting: false)
    }

    func cancel(id: UUID) {
        alarms.removeValue(forKey: id)
    }
}
