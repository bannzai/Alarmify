import AlarmKit
import Foundation
import SwiftUI

/// 整理の判定に使う、登録済みアラームの見え方。AlarmKit の `Alarm` が準拠し、ユニットテストはメモリ上の値を渡す
/// (`Alarm` は外部から生成できないため、判定ロジックはこのプロトコル越しに書く)
protocol RegisteredAlarm: Sendable {
    var id: UUID { get }
    /// 固定日時のアラームの発火時刻。繰り返し・カウントダウンのアラームでは nil
    var fixedFireDate: Date? { get }
    /// 鳴動中かどうか。鳴っている最中のアラームは整理で取り消さない
    var isAlerting: Bool { get }
}

extension Alarm: RegisteredAlarm {
    var fixedFireDate: Date? {
        if case .fixed(let fireDate)? = schedule { return fireDate }
        return nil
    }

    var isAlerting: Bool {
        state == .alerting
    }
}

/// `AlarmKitScheduler` が依存する外部リソース。
/// 実体は `AlarmManager.shared` と App Group の UserDefaults で、ユニットテストはメモリ上の実装に差し替える
/// (`AlarmManager.shared` はテストホストで権限の状態に左右され、`Alarm` は外部から生成できないため)。
/// `@unchecked` なのは UserDefaults がスレッドセーフ (Apple のドキュメント) でありながら Sendable 注釈を持たないため
struct AlarmSchedulerDependencies: @unchecked Sendable {
    /// 登録済みアラーム。取得に失敗したら throw する
    var registeredAlarms: @Sendable () throws -> [any RegisteredAlarm]
    /// 固定日時のアラームを 1 件登録する。引数は (id, 発火日時, タイトル)
    var schedule: @Sendable (UUID, Date, String) async throws -> Void
    var cancel: @Sendable (UUID) throws -> Void
    /// タイトル (`AlarmTitleStore`) と適用結果の報告キュー (`AlarmApplyReportQueue`) の保存先
    var userDefaults: UserDefaults
    /// 保存先の書き換えを app 本体と Extension の間で直列化するロック
    var storeLock: SharedStoreLock
    var now: @Sendable () -> Date

    static let live = AlarmSchedulerDependencies(
        registeredAlarms: { try AlarmManager.shared.alarms },
        schedule: { id, fireDate, title in
            let attributes = AlarmAttributes<AlarmifyAlarmMetadata>(
                presentation: AlarmPresentation(alert: AlarmKitScheduler.alert(title: title)),
                metadata: AlarmifyAlarmMetadata(title: title),
                tintColor: .signal
            )
            _ = try await AlarmManager.shared.schedule(
                id: id,
                configuration: .alarm(
                    schedule: .fixed(fireDate),
                    attributes: attributes,
                    sound: .default
                )
            )
        },
        cancel: { id in try AlarmManager.shared.cancel(id: id) },
        userDefaults: AppGroup.userDefaults,
        storeLock: .appGroup,
        now: { .now }
    )
}

/// AlarmKit への登録・取消。app 本体と Notification Service Extension の両方から同じ経路で呼ぶ
enum AlarmKitScheduler {
    static var authorizationState: AlarmManager.AuthorizationState {
        AlarmManager.shared.authorizationState
    }

    static func requestAuthorization() async throws -> AlarmManager.AuthorizationState {
        try await AlarmManager.shared.requestAuthorization()
    }

    /// 登録済みアラーム。取得に失敗した場合は空 (表示用途のため例外にしない)
    static var alarms: [Alarm] {
        (try? AlarmManager.shared.alarms) ?? []
    }

    /// 登録済みアラームの変化 (登録・取消・発火)。別プロセス (Notification Service Extension) からの登録も AlarmKit 側で 1 つに合流して届くため、
    /// ホームはこれを購読して push で届いたアラームをその場で表示に反映する
    static var alarmUpdates: some AsyncSequence<[Alarm], Never> {
        AlarmManager.shared.alarmUpdates
    }

    /// AlarmRequest を AlarmKit に反映し、結果 (登録できた / 失敗した / 取り消した) を報告キューへ積む。
    /// 同じ id の再 schedule は登録し直し (取消 → 登録) で上書きするため、同じ指示の再送は冪等。
    /// 報告キューは push の到着元 (Notification Service Extension / background push / 開発者メニュー) を問わず app 本体がバックエンドへ送る
    static func apply(_ request: AlarmRequest, dependencies: AlarmSchedulerDependencies = .live) async throws {
        let reports = AlarmApplyReportQueue(userDefaults: dependencies.userDefaults, lock: dependencies.storeLock)
        do {
            switch request.action {
            case .schedule:
                guard let fireDate = request.fireDate else { return }
                try await schedule(id: request.id, fireDate: fireDate, title: request.title ?? "Signalarm", dependencies: dependencies)
            case .cancel:
                try cancel(id: request.id, dependencies: dependencies)
            }
            reports.enqueue(AlarmApplyReport(alarmID: request.id, action: request.action, result: .applied, error: nil, occurredAt: dependencies.now(), fireAt: request.fireDate))
        } catch {
            reports.enqueue(AlarmApplyReport(
                alarmID: request.id,
                action: request.action,
                result: .failed,
                error: String(error.localizedDescription.prefix(AlarmApplyReport.maxErrorLength)),
                occurredAt: dependencies.now(),
                fireAt: request.fireDate
            ))
            throw error
        }
    }

    /// 固定日時のアラームを登録する。同じ id が登録済みなら取り消してから登録する。
    /// 登録の前に発火済み・過去日時のアラームを整理し、外部サービスからの登録で AlarmKit の件数上限に達しにくくする
    /// (`.claude/rules/ios-alarmkit-constraints.md`)。整理しても上限に達した場合のエラー (`maximumLimitReached`) はそのまま投げ、
    /// 未来のアラームを勝手に消して枠を作ることはしない
    static func schedule(id: UUID, fireDate: Date, title: String, dependencies: AlarmSchedulerDependencies = .live) async throws {
        let titles = AlarmTitleStore(userDefaults: dependencies.userDefaults, lock: dependencies.storeLock)
        // 一覧の取得に失敗しても登録は進める (整理は次の登録で再試行できる)
        if let alarms = try? dependencies.registeredAlarms() {
            for expiredID in expiredAlarmIDs(alarms: alarms, now: dependencies.now()) {
                try? dependencies.cancel(expiredID)
                titles.remove(id: expiredID)
            }
        }
        try? dependencies.cancel(id)
        try await dependencies.schedule(id, fireDate, title)
        titles.save(title: title, id: id)
    }

    static func cancel(id: UUID, dependencies: AlarmSchedulerDependencies = .live) throws {
        try dependencies.cancel(id)
        AlarmTitleStore(userDefaults: dependencies.userDefaults, lock: dependencies.storeLock).remove(id: id)
    }

    /// 整理の対象にする id。発火時刻を過ぎた固定日時のアラームのうち、鳴動中でないもの
    /// (発火して止められた後も一覧に残るものと、端末の停止中に発火時刻を過ぎて鳴らなかったものの両方が該当する)
    static func expiredAlarmIDs(alarms: [any RegisteredAlarm], now: Date) -> [UUID] {
        alarms.compactMap { alarm in
            guard let fireDate = alarm.fixedFireDate, fireDate < now, !alarm.isAlerting else { return nil }
            return alarm.id
        }
    }

    /// 発火画面の alert を作成する。
    /// stopButton を渡さない init は iOS 26.1 以降にしか存在しないため、iOS 26.0 のみ stopButton 付きの init へフォールバックする
    /// (iOS 26.1 以降では指定した stopButton は使われず、停止 UI はシステム標準描画になる)
    static func alert(title: String) -> AlarmPresentation.Alert {
        let resource = LocalizedStringResource(String.LocalizationValue(title))
        if #available(iOS 26.1, *) {
            return .init(title: resource)
        } else {
            // ja: 止める
            return .init(title: resource, stopButton: .init(text: "Stop", textColor: .white, systemImageName: "stop.circle"))
        }
    }
}
