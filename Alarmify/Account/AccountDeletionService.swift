import Foundation

/// アカウントとサーバー上のデータの削除。テストと Preview で差し替えられるよう protocol にする
protocol AccountDeletionService: Sendable {
    func deleteAccount(credential: AccountCredential) async throws
}

/// アカウント削除の失敗理由
enum AccountDeletionError: Error, LocalizedError, Equatable {
    /// サーバーがエラーを返した。message はサーバーの文言 (ユーザー入力と同じく翻訳対象にしない)
    case server(message: String)
    /// HTTP レスポンスとして解釈できなかった
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .server(let message):
            return message
        case .invalidResponse:
            // ja: サーバーからの応答を読み取れませんでした。時間をおいて試してください
            return String(localized: "Could not read the response from the server. Please try again later.")
        }
    }
}

/// Functions の Callable (`deleteAccount`) を呼んでアカウントを削除する。
/// Callable のプロトコル (`{"data": ...}` を POST し、成功時は `{"result": ...}` が返る) に合わせて組み立てる
struct RemoteAccountDeletionService: AccountDeletionService {
    private let endpoint: URL
    private let session: URLSession

    init(endpoint: URL = BackendEndpoint.deleteAccount, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    func deleteAccount(credential: AccountCredential) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(credential.idToken)", forHTTPHeaderField: "Authorization")
        // 削除対象は ID トークンの uid でサーバーが決めるため、パラメータは送らない
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data": [String: String]()])

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AccountDeletionError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw AccountDeletionError.server(message: Self.errorMessage(from: data) ?? "HTTP \(httpResponse.statusCode)")
        }
    }

    /// Callable のエラー本文 (`{"error": {"message": ...}}`) から文言を取り出す
    private static func errorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return nil
        }
        return message
    }
}
