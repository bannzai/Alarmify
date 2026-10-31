import XCTest
@testable import Alarmify

/// 開発者メニューの件数上限を測る一括登録 (`DebugAlarmLimitProbe`) の、件数・時刻の組み立て、結果の集計、一括取り消しのテスト。
/// AlarmKit 本体には触れず、メモリ上の偽の登録先 (`FakeAlarmStore`) に差し替えて検証する
final class DebugAlarmLimitProbeTests: XCTestCase {
    /// テスト対象が読む現在時刻 (`dependencies.now`)。発火時刻の期待値を実行時刻に左右されず書けるよう固定する。値は他のテスト (`AlarmKitSchedulerTests` 等) と揃えただけで意味は無い
    private let now = Date(timeIntervalSince1970: 1_788_418_800)
    /// AlarmKit の代わりの登録先。`setUp` でテストごとに作り直すため、前のテストで登録したアラームは残らない
    private var store: FakeAlarmStore!
    /// テスト用アラームの id の記録先。`setUp` でテストごとに空の suite を作るため、記録はテストをまたがない
    private var userDefaults: UserDefaults!
    /// テストは 1 プロセスで順に動き、競合する書き手がいないためロックしない
    private let noLock = SharedStoreLock(fileURL: nil)

    override func setUp() {
        super.setUp()
        store = FakeAlarmStore()
        // App Group の実体に書かず、テストごとに空の suite を使う
        let suiteName = "DebugAlarmLimitProbeTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    /// テスト対象に渡す依存。AlarmKit・App Group・現在時刻の代わりに `store`・`userDefaults`・`now` を使わせる
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

    func testCountAcceptsOnlyNumbersInRange() {
        XCTAssertEqual(DebugAlarmLimitProbe.count(text: "3"), 3)
        XCTAssertEqual(DebugAlarmLimitProbe.count(text: " 12 "), 12)
        XCTAssertEqual(DebugAlarmLimitProbe.count(text: "\(DebugAlarmLimitProbe.maxCount)"), DebugAlarmLimitProbe.maxCount)
        XCTAssertNil(DebugAlarmLimitProbe.count(text: "0"))
        XCTAssertNil(DebugAlarmLimitProbe.count(text: "-1"))
        XCTAssertNil(DebugAlarmLimitProbe.count(text: "\(DebugAlarmLimitProbe.maxCount + 1)"))
        XCTAssertNil(DebugAlarmLimitProbe.count(text: "abc"))
        XCTAssertNil(DebugAlarmLimitProbe.count(text: ""))
    }

    func testEveryMinuteFiresOneMinuteApartStartingOneMinuteLater() {
        XCTAssertEqual(
            DebugAlarmLimitProbe.fireDates(spacing: .everyMinute, count: 3, now: now),
            [now.addingTimeInterval(60), now.addingTimeInterval(120), now.addingTimeInterval(180)]
        )
    }

    func testSameTimeFiresAllAtOneTime() {
        let fireDate = now.addingTimeInterval(DebugAlarmLimitProbe.sameTimeFireInterval)
        XCTAssertEqual(DebugAlarmLimitProbe.fireDates(spacing: .sameTime, count: 3, now: now), [fireDate, fireDate, fireDate])
    }

    func testScheduleRegistersEveryAlarmAndRemembersTheirIDs() async throws {
        let outcome = try await DebugAlarmLimitProbe.schedule(spacing: .everyMinute, count: 3, dependencies: dependencies)

        XCTAssertEqual(outcome, DebugAlarmLimitProbe.Outcome(requestedCount: 3, scheduledCount: 3, failure: nil, registeredCount: 3))
        XCTAssertEqual(store.alarms.count, 3)
        XCTAssertEqual(Set(DebugAlarmLimitProbe.alarmIDs(userDefaults: userDefaults)), Set(store.alarms.keys))
        XCTAssertEqual(Set(store.alarms.values.compactMap(\.fireDate)), Set(DebugAlarmLimitProbe.fireDates(spacing: .everyMinute, count: 3, now: now)))
    }

    func testScheduleStopsAtTheLimitAndReportsThePosition() async throws {
        store.maximumCount = 3
        store.alarms[UUID()] = FakeAlarmStore.Entry(fireDate: now.addingTimeInterval(600), title: "Deploy finished", isAlerting: false)

        let outcome = try await DebugAlarmLimitProbe.schedule(spacing: .sameTime, count: 5, dependencies: dependencies)

        XCTAssertEqual(
            outcome,
            DebugAlarmLimitProbe.Outcome(requestedCount: 5, scheduledCount: 2, failure: .maximumLimitReached, registeredCount: 3),
            "上限の件数は既存のアラームを含む登録済みの全件で読む"
        )
        XCTAssertEqual(store.scheduleCount, 3, "3 件目で失敗したら 4 件目以降は登録しない")
        XCTAssertEqual(DebugAlarmLimitProbe.alarmIDs(userDefaults: userDefaults).count, 2, "失敗した 1 件は記録しない")
    }

    func testScheduleReportsOtherErrorsSeparatelyFromTheLimit() async throws {
        store.scheduleError = .tooLongDescription

        let outcome = try await DebugAlarmLimitProbe.schedule(spacing: .everyMinute, count: 3, dependencies: dependencies)

        XCTAssertEqual(outcome, DebugAlarmLimitProbe.Outcome(
            requestedCount: 3,
            scheduledCount: 0,
            failure: .other(FakeAlarmStore.Failure.tooLongDescription.localizedDescription),
            registeredCount: 0
        ))
    }

    func testCancelAllRemovesOnlyTestAlarmsAndIsIdempotent() async throws {
        let realAlarmID = UUID()
        store.alarms[realAlarmID] = FakeAlarmStore.Entry(fireDate: now.addingTimeInterval(600), title: "Deploy finished", isAlerting: false)
        try await DebugAlarmLimitProbe.schedule(spacing: .sameTime, count: 3, dependencies: dependencies)

        XCTAssertEqual(try DebugAlarmLimitProbe.cancelAll(dependencies: dependencies), 3)
        XCTAssertEqual(Set(store.alarms.keys), [realAlarmID], "外部サービスから登録されたアラームは取り消さない")
        XCTAssertTrue(DebugAlarmLimitProbe.alarmIDs(userDefaults: userDefaults).isEmpty)

        XCTAssertEqual(try DebugAlarmLimitProbe.cancelAll(dependencies: dependencies), 0)
        XCTAssertEqual(Set(store.alarms.keys), [realAlarmID])
    }

    func testCancelAllSkipsTestAlarmsThatAreNoLongerRegistered() async throws {
        try await DebugAlarmLimitProbe.schedule(spacing: .everyMinute, count: 2, dependencies: dependencies)
        let firedID = try XCTUnwrap(DebugAlarmLimitProbe.alarmIDs(userDefaults: userDefaults).first)
        store.alarms.removeValue(forKey: firedID)

        XCTAssertEqual(try DebugAlarmLimitProbe.cancelAll(dependencies: dependencies), 1)
        XCTAssertTrue(store.alarms.isEmpty)
        XCTAssertTrue(DebugAlarmLimitProbe.alarmIDs(userDefaults: userDefaults).isEmpty)
    }
}
