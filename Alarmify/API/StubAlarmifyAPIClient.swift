import Foundation

/// バックエンドを起動せずに API トークン画面を動作確認するための、メモリ上のスタブ。
/// 開発者メニューからのみ有効化する (`.claude/rules/debug-menu-for-verification.md`)
actor StubAlarmifyAPIClient: AlarmifyAPIClient {
    /// 無料プランで同時に持てる API トークンの数 (functions/src/lib/plan.ts の planLimits.free.apiTokens と同じ)。
    /// 上限に達した時のペイウォール表示をバックエンド無しで確認できるよう、スタブも同じ上限で 403 を返す
    static let freePlanAPITokenLimit = 1

    private var tokens: [APIToken] = []
    private var registeredFCMRegistrationToken: String?
    /// 発行済みトークンの連番。プレフィックスを毎回変えて一覧で見分けられるようにする
    private var issuedCount = 0
    /// 受け取った適用結果の報告 (アラーム id と操作ごとに最新の 1 件)。本物のサーバーと同じく上書きで持つ
    private(set) var reports: [AlarmApplyReport] = []

    func registerDevice(fcmRegistrationToken: String) async throws {
        registeredFCMRegistrationToken = fcmRegistrationToken
    }

    func apiTokens() async throws -> [APIToken] {
        tokens
    }

    func issueAPIToken() async throws -> IssuedAPIToken {
        guard tokens.count < Self.freePlanAPITokenLimit else {
            // 本物のバックエンド (appApi の POST /v1/api-tokens) と同じ応答
            throw AlarmifyAPIError.server(
                statusCode: 403,
                code: AlarmifyAPIError.planLimitExceededCode,
                message: "free プランで発行できる API トークンは \(Self.freePlanAPITokenLimit) 個までです"
            )
        }
        issuedCount += 1
        let suffix = String(format: "%04x", issuedCount)
        let token = APIToken(id: "stub-\(suffix)", name: "default", prefix: "alm_\(suffix)", createdAt: .now, lastUsedAt: nil)
        tokens.append(token)
        return IssuedAPIToken(token: token, secret: "alm_\(suffix)_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))")
    }

    func revokeAPIToken(id: String) async throws {
        tokens.removeAll { $0.id == id }
    }

    /// ホームの履歴の表示を確認するための見本。外部サービスからの登録 1 件と取り消し 1 件を返す
    /// (バックエンドが正を持つ値の代わりではなく、スタブを選んだ時だけ使う fixture)
    func alarmHistory(limit: Int) async throws -> [AlarmHistoryEntry] {
        let entries = [
            AlarmHistoryEntry(
                id: "3b0e0c6e-9f1b-4c0a-9e7d-1f2a3b4c5d6e",
                status: .scheduled,
                title: "Deploy finished",
                fireAt: .now.addingTimeInterval(30 * 60),
                createdAt: .now.addingTimeInterval(-60),
                tokenID: "stub-0001",
                delivery: AlarmHistoryEntry.Delivery(successCount: 1, failureCount: 0),
                deviceReports: [
                    AlarmHistoryEntry.DeviceReport(deviceID: DeviceIdentifier.current, action: .schedule, result: .applied, error: nil, occurredAt: .now.addingTimeInterval(-55)),
                ]
            ),
            AlarmHistoryEntry(
                id: "7f6d8c1a-2b3e-4f50-9a61-0b1c2d3e4f5a",
                status: .canceled,
                title: "Nightly backup",
                fireAt: .now.addingTimeInterval(-2 * 60 * 60),
                createdAt: .now.addingTimeInterval(-3 * 60 * 60),
                tokenID: "stub-0001",
                delivery: AlarmHistoryEntry.Delivery(successCount: 1, failureCount: 0),
                deviceReports: []
            ),
        ]
        return Array(entries.prefix(limit))
    }

    func reportAlarmApply(_ report: AlarmApplyReport) async throws {
        reports.removeAll { $0.alarmID == report.alarmID && $0.action == report.action }
        reports.append(report)
    }

    /// メモリ上のデータを消すだけで、Firebase Auth の実アカウントには触れない (AccountSession 側でスタブ時のサインアウトを省く)
    func deleteAccount() async throws {
        tokens.removeAll()
        registeredFCMRegistrationToken = nil
        reports.removeAll()
    }
}
