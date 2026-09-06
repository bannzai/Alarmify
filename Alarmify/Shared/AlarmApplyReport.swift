import Foundation

/// 端末が `AlarmRequest` を AlarmKit へ反映した結果 1 件。バックエンドの `POST /v1/alarms/{id}/device-reports` の body に対応する
struct AlarmApplyReport: Codable, Equatable, Sendable {
    enum Result: String, Codable, Sendable {
        case applied
        case failed
    }

    var alarmID: UUID
    var action: AlarmRequest.Action
    var result: Result
    /// `failed` の時のエラーの説明。`applied` では nil
    var error: String?
    /// 端末が反映を行った時刻
    var occurredAt: Date
}

/// バックエンドへ未送信の適用結果。
/// Notification Service Extension は Firebase Auth の ID トークンを持てない (keychain を共有していない) ため、
/// 到着元を問わず App Group に積んでおき、app 本体がサインイン済みの時にまとめて送る
struct AlarmApplyReportQueue {
    private static let key = "pendingAlarmApplyReports"

    let userDefaults: UserDefaults

    static let shared = AlarmApplyReportQueue(userDefaults: AppGroup.userDefaults)

    /// 未送信の報告。古い順
    var pending: [AlarmApplyReport] {
        guard let data = userDefaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([AlarmApplyReport].self, from: data)) ?? []
    }

    /// 同じアラーム・同じ操作の報告は最新の 1 件だけ残す (サーバー側も端末ごとに最新の結果を 1 件持つため、古い結果を送る意味がない)
    func enqueue(_ report: AlarmApplyReport) {
        var reports = pending.filter { !($0.alarmID == report.alarmID && $0.action == report.action) }
        reports.append(report)
        save(reports)
    }

    /// 送信できた (またはサーバーに記録先が無かった) 報告を取り除く
    func remove(_ report: AlarmApplyReport) {
        save(pending.filter { $0 != report })
    }

    private func save(_ reports: [AlarmApplyReport]) {
        if reports.isEmpty {
            userDefaults.removeObject(forKey: Self.key)
            return
        }
        // Codable の Date は JSON では倍精度の秒になり、往復で値が変わらない
        userDefaults.set(try? JSONEncoder().encode(reports), forKey: Self.key)
    }
}
