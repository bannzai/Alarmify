import Foundation

/// バックエンドを起動せずに API トークン画面を動作確認するための、メモリ上のスタブ。
/// 開発者メニューからのみ有効化する (`.claude/rules/debug-menu-for-verification.md`)
actor StubAlarmifyAPIClient: AlarmifyAPIClient {
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
        issuedCount += 1
        let suffix = String(format: "%04x", issuedCount)
        let token = APIToken(id: "stub-\(suffix)", name: "default", prefix: "alm_\(suffix)", createdAt: .now, lastUsedAt: nil)
        tokens.append(token)
        return IssuedAPIToken(token: token, secret: "alm_\(suffix)_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))")
    }

    func revokeAPIToken(id: String) async throws {
        tokens.removeAll { $0.id == id }
    }
}
