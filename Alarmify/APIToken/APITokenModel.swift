import Foundation
import Observation

/// API トークン画面の状態。一覧の取得・発行・失効を行い、エラーはサーバーのメッセージをそのまま保持する
@MainActor
@Observable
final class APITokenModel {
    private let session: AccountSession

    private(set) var tokens: [APIToken] = []
    private(set) var loading = false
    /// 直前の操作で発生したエラーの説明。成功したら nil に戻す
    private(set) var errorMessage: String?
    /// 発行直後のトークン。平文を表示できるのはこの 1 回だけなので、画面から明示的に閉じるまで保持する
    private(set) var issued: IssuedAPIToken?
    /// 表示中のペイウォールの文脈。発行が無料プランの上限 (`plan_limit_exceeded`) で拒否された時に立て、画面が sheet で開く。
    /// 閉じる操作で画面側から nil に戻すため設定可能にする
    var paywallTrigger: PaywallTrigger?

    /// 既定は共有のアカウント状態。テストは専用のインスタンスを渡す
    /// (既定値に `.shared` を直接書くと、既定値が nonisolated な文脈で評価されて main actor 隔離の警告になる)
    init(session: AccountSession? = nil) {
        self.session = session ?? .shared
    }

    /// 発行直後のトークンをそのまま使える curl の例。未発行なら nil。
    /// fire_at は呼ばれた瞬間の 5 分後になるため、コピーする時はその場で読み直す
    var curlExample: String? {
        guard let issued else { return nil }
        return APITokenUsageExample.curl(
            secret: issued.secret,
            backend: session.settings.backend,
            fireDate: .now.addingTimeInterval(300)
        )
    }

    func load() async {
        loading = true
        defer { loading = false }
        do {
            tokens = try await session.client.apiTokens()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func issue() async {
        loading = true
        defer { loading = false }
        do {
            issued = try await session.client.issueAPIToken()
            tokens = try await session.client.apiTokens()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            // 無料プランの上限で拒否された時はペイウォールへ誘導する (サーバーの上限判定が正で、アプリ側では数えない)
            if (error as? AlarmifyAPIError)?.isPlanLimitExceeded == true {
                paywallTrigger = .freeQuotaExceeded
            }
        }
    }

    func revoke(id: String) async {
        loading = true
        defer { loading = false }
        do {
            try await session.client.revokeAPIToken(id: id)
            // 失効させたトークンの平文を表示したままにしない
            if issued?.token.id == id { issued = nil }
            tokens = try await session.client.apiTokens()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 発行直後の平文表示を閉じる
    func dismissIssued() {
        issued = nil
    }
}
