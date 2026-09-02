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
    /// 保存済みの認証情報から ID トークンを取得できなかった (refresh トークンの失効・取り消し)
    case authenticationExpired
    /// アカウントの認証がまだ実装されていない (匿名認証の実装で解消する)
    case authenticationUnavailable

    var errorDescription: String? {
        switch self {
        case .server(let message):
            return message
        case .invalidResponse:
            // ja: サーバーからの応答を読み取れませんでした。時間をおいて試してください
            return String(localized: "Could not read the response from the server. Please try again later.")
        case .authenticationExpired:
            // ja: アカウントの認証が切れています。アプリを再起動して試してください
            return String(localized: "Your session has expired. Restart the app and try again.")
        case .authenticationUnavailable:
            // ja: この端末ではアカウントの認証を利用できません
            return String(localized: "Account authentication is not available on this device.")
        }
    }
}

/// Functions の Callable (`deleteAccount`) を呼んでアカウントを削除する。
/// Callable のプロトコル (`{"data": ...}` を POST し、成功時は `{"result": ...}` が返る) に合わせて組み立てる
struct RemoteAccountDeletionService: AccountDeletionService {
    private let endpoint: URL
    private let idTokenProvider: AccountIDTokenProvider
    private let session: URLSession

    init(
        endpoint: URL = BackendEndpoint.deleteAccount,
        idTokenProvider: AccountIDTokenProvider = FirebaseIDTokenProvider(),
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.idTokenProvider = idTokenProvider
        self.session = session
    }

    func deleteAccount(credential: AccountCredential) async throws {
        // ID トークンは短時間で失効するため、保存した値ではなく呼び出しの直前に取得したものを使う
        let idToken = try await idTokenProvider.idToken(for: credential)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
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
