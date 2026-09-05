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

    /// メモリ上のデータを消すだけで、Firebase Auth の実アカウントには触れない (AccountSession 側でスタブ時のサインアウトを省く)
    func deleteAccount() async throws {
        tokens.removeAll()
        registeredFCMRegistrationToken = nil
    }
}
