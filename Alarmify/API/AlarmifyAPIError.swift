import Foundation

/// アプリ → バックエンドの通信で発生したエラー。
/// サーバーが返したメッセージは加工せずそのまま保持し、画面にもそのまま表示する
enum AlarmifyAPIError: Error, Equatable, LocalizedError {
    /// Firebase Auth のサインインが終わっておらず、ID トークンを付けられない
    case notSignedIn
    /// HTTP のエラー応答。message はサーバーが返した内容 (JSON の `error.message`、無ければ body の生文字列)
    case server(statusCode: Int, message: String)
    /// 応答が期待した JSON ではない
    case invalidResponse(detail: String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            // ja: サインインが完了していません
            return String(localized: "Not signed in")
        case .server(let statusCode, let message):
            return "HTTP \(statusCode): \(message)"
        case .invalidResponse(let detail):
            return detail
        }
    }
}
