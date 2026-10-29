import AlarmKit
import Foundation

/// 開発者メニューから AlarmKit の件数上限 (`AlarmManager.AlarmError.maximumLimitReached`) を実機で測る一括登録 (`.claude/rules/debug-menu-for-verification.md`)。
/// Apple は上限の件数を公表しておらず端末の状態で変わるとしている (https://developer.apple.com/forums/thread/797158 ) ため、
/// 1 件ずつ登録して何件目で失敗したかを返す。登録は本物のアラームと同じ `AlarmKitScheduler.schedule` を通し、
/// 登録したテスト用アラームの id だけを覚えておき、一括取り消しはその id に限る (外部サービスから登録された本物のアラームを消さない)
enum DebugAlarmLimitProbe {
    /// 一括登録・一括取り消しを始められなかった理由。1 件ごとの登録の失敗は投げずに `Outcome.failure` で返す
    enum Error: Swift.Error, LocalizedError {
        /// App Store 配布 (開発者メニューが解放されていない) では何もしない
        case unavailable

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "The developer menu is not available in this build."
            }
        }
    }

    /// 発火時刻の並べ方。分散した時と集中した時で上限が違うかを比べるために 2 通り用意する
    enum Spacing: Equatable {
        /// 1 分後・2 分後…N 分後に 1 件ずつ
        case everyMinute
        /// N 件すべてを同じ時刻 (`sameTimeFireInterval` 秒後) に
        case sameTime
    }

    /// 1 件の登録に失敗した理由
    enum Failure: Equatable {
        case maximumLimitReached
        /// 件数上限以外のエラー。値はエラーの説明
        case other(String)
    }

    /// 一括登録の結果。失敗したら以降を登録せずに止めるため、失敗した位置は `scheduledCount + 1` 件目になる
    struct Outcome: Equatable {
        /// 登録を求めた件数
        var requestedCount: Int
        /// 登録に成功した件数
        var scheduledCount: Int
        /// 途中で失敗した時の理由。全件成功なら nil
        var failure: Failure?
        /// 登録を終えた時点で AlarmKit に登録されていた全アラームの件数。取得に失敗したら nil。
        /// 既存の本物のアラームと、登録中に発火時刻を過ぎて整理されたアラームがあると `scheduledCount` と食い違うため、上限の件数はこちらで読む
        var registeredCount: Int?
    }

    /// 1 回に登録できる件数の上限。Pro の月間の登録上限 (1000 回。`documents/PROJECT.md`「課金設計」) を超える件数が
    /// 外部サービス経由で 1 台に溜まることは無いため、それ以上は測る意味が無い
    static let maxCount = 1000
    /// 同時刻に登録する時の発火までの秒数。上限の件数を登録し終えるまでに発火時刻を過ぎず、
    /// 取り消し忘れても長く待たずに鳴って気づける数分後にする
    static let sameTimeFireInterval: TimeInterval = 5 * 60
    /// 登録したテスト用アラームの id を保存する UserDefaults キー
    static let alarmIDsKey = "debugAlarmLimitProbeAlarmIDs"

    /// 開発者メニューで入力された件数。1〜`maxCount` の整数でなければ nil
    static func count(text: String) -> Int? {
        guard let count = Int(text.trimmingCharacters(in: .whitespaces)), (1...maxCount).contains(count) else { return nil }
        return count
    }

    /// 登録する各アラームの発火時刻。`now` を起点に `spacing` の並べ方で `count` 件分を返す
    static func fireDates(spacing: Spacing, count: Int, now: Date) -> [Date] {
        switch spacing {
        case .everyMinute:
            return (1...count).map { now.addingTimeInterval(TimeInterval($0) * 60) }
        case .sameTime:
            return Array(repeating: now.addingTimeInterval(sameTimeFireInterval), count: count)
        }
    }

    /// `count` 件のテスト用アラームを 1 件ずつ登録し、最初の失敗で止めて結果を返す。
    /// 登録に成功した id は `dependencies.userDefaults` に追記し、`cancelAll` で取り消せるようにする
    @discardableResult
    static func schedule(spacing: Spacing, count: Int, dependencies: AlarmSchedulerDependencies = .live) async throws -> Outcome {
        guard DeveloperMenu.isAvailable else { throw Error.unavailable }
        for (index, fireDate) in fireDates(spacing: spacing, count: count, now: dependencies.now()).enumerated() {
            let id = UUID()
            do {
                try await AlarmKitScheduler.schedule(id: id, fireDate: fireDate, title: "Limit probe \(index + 1)/\(count)", dependencies: dependencies)
            } catch {
                return Outcome(requestedCount: count, scheduledCount: index, failure: failure(error: error), registeredCount: try? dependencies.registeredAlarms().count)
            }
            saveAlarmIDs(alarmIDs: alarmIDs(userDefaults: dependencies.userDefaults) + [id], userDefaults: dependencies.userDefaults)
        }
        return Outcome(requestedCount: count, scheduledCount: count, failure: nil, registeredCount: try? dependencies.registeredAlarms().count)
    }

    /// テスト用に登録したアラームのうち、AlarmKit にまだ残っているものを取り消し、取り消した件数を返す。
    /// 発火済みで AlarmKit から消えた id は取り消さずに記録から外すため、続けて実行しても失敗せず 0 件を返す (冪等)。
    /// 取り消しに失敗した時は、まだ取り消していない id を記録に残して throw する
    @discardableResult
    static func cancelAll(dependencies: AlarmSchedulerDependencies = .live) throws -> Int {
        guard DeveloperMenu.isAvailable else { throw Error.unavailable }
        let registeredIDs = Set(try dependencies.registeredAlarms().map(\.id))
        var remainingIDs = alarmIDs(userDefaults: dependencies.userDefaults)
        defer { saveAlarmIDs(alarmIDs: remainingIDs, userDefaults: dependencies.userDefaults) }
        var cancelledCount = 0
        while let id = remainingIDs.first {
            if registeredIDs.contains(id) {
                try AlarmKitScheduler.cancel(id: id, dependencies: dependencies)
                cancelledCount += 1
            }
            remainingIDs.removeFirst()
        }
        return cancelledCount
    }

    /// 登録したテスト用アラームの id
    static func alarmIDs(userDefaults: UserDefaults) -> [UUID] {
        (userDefaults.stringArray(forKey: alarmIDsKey) ?? []).compactMap(UUID.init(uuidString:))
    }

    /// 登録したテスト用アラームの id の記録を `alarmIDs` で置き換える
    private static func saveAlarmIDs(alarmIDs: [UUID], userDefaults: UserDefaults) {
        userDefaults.set(alarmIDs.map(\.uuidString), forKey: alarmIDsKey)
    }

    /// 登録のエラーを、件数上限かそれ以外かに分ける
    private static func failure(error: any Swift.Error) -> Failure {
        if error as? AlarmManager.AlarmError == .maximumLimitReached {
            return .maximumLimitReached
        }
        return .other(error.localizedDescription)
    }
}
