import Foundation

/// アプリ → バックエンドの通信で発生したエラー。
/// サーバーが返したメッセージは加工せずそのまま保持し、画面にもそのまま表示する
enum AlarmifyAPIError: Error, Equatable, LocalizedError {
    /// Firebase Auth のサインインが終わっておらず、ID トークンを付けられない
    case notSignedIn
    /// HTTP のエラー応答。code はサーバーが返した `error.code` (`plan_limit_exceeded` 等。無ければ nil)、
    /// message はサーバーが返した内容 (JSON の `error.message`、無ければ body の生文字列)
    case server(statusCode: Int, code: String?, message: String)
    /// 応答が期待した JSON ではない
    case invalidResponse(detail: String)

    /// プランの上限に達した応答のコード。無料プランのトークン数・月間のアラーム数の上限 (functions/src/lib/plan.ts) で返る
    static let planLimitExceededCode = "plan_limit_exceeded"

    /// プランの上限に達した応答かどうか。ペイウォールへ誘導する判定に使う
    var isPlanLimitExceeded: Bool {
        if case .server(_, Self.planLimitExceededCode?, _) = self {
            return true
        }
        return false
    }

    /// 適用結果の報告 (`POST /v1/alarms/{id}/device-reports`) をサーバーが受け付けない応答のコード。
    /// アラームがサーバーに無い (`alarm_not_found`)、この端末が登録されていない (`device_not_found`)、
    /// 再スケジュール後に届いた前の登録の報告 (`alarm_revision_mismatch`)、内容がスキーマに合わない (`invalid_argument`)
    static let alarmApplyReportRejectedCodes: Set<String> = ["alarm_not_found", "device_not_found", "alarm_revision_mismatch", "invalid_argument"]

    /// 適用結果の報告を送り直しても受け付けられない応答かどうか。報告をキューから捨ててよい判定に使う (残すと後ろの報告まで止める)。
    /// 同じ 404 でも code が `not_found` の応答はエンドポイント自体が無い古いデプロイの appApi から来るため対象にせず、報告を残して後で送り直す
    var rejectsAlarmApplyReport: Bool {
        if case .server(_, let code?, _) = self {
            return Self.alarmApplyReportRejectedCodes.contains(code)
        }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            // ja: サインインが完了していません
            return String(localized: "Not signed in")
        case .server(let statusCode, _, let message):
            return "HTTP \(statusCode): \(message)"
        case .invalidResponse(let detail):
            return detail
        }
    }
}
