import Foundation

/// アプリ向けバックエンド API の呼び出し口。
/// 実通信 (`URLSessionAlarmifyAPIClient`) と検証用スタブ (`StubAlarmifyAPIClient`) を差し替えられるようにプロトコルで定義する
protocol AlarmifyAPIClient: Sendable {
    /// FCM 登録トークンをこの端末の配送先として登録する
    func registerDevice(fcmRegistrationToken: String) async throws
    /// 発行済み API トークンの一覧を取得する
    func apiTokens() async throws -> [APIToken]
    /// API トークンを新しく発行する。平文が返るのはこの応答だけ
    func issueAPIToken() async throws -> IssuedAPIToken
    /// API トークンを失効させる
    func revokeAPIToken(id: String) async throws
    /// 呼び出し元自身のアカウントとサーバー上のデータ (API トークン・配送先・アラーム履歴) を削除する
    func deleteAccount() async throws
}

/// URLSession で Cloud Functions のアプリ向け API を叩く実装。
/// Firebase Auth の ID トークンを `Authorization: Bearer` に付けて認証する。
/// Firebase への依存は `idToken` クロージャに閉じ込め、テストでは差し替える
struct URLSessionAlarmifyAPIClient: AlarmifyAPIClient {
    let backend: AlarmifyBackend
    let session: URLSession
    /// Firebase Auth の ID トークンを返す。未サインインなら nil
    let idToken: @Sendable () async throws -> String?

    init(
        backend: AlarmifyBackend,
        session: URLSession = .shared,
        idToken: @escaping @Sendable () async throws -> String?
    ) {
        self.backend = backend
        self.session = session
        self.idToken = idToken
    }

    func registerDevice(fcmRegistrationToken: String) async throws {
        _ = try await send(
            method: "POST",
            path: "/v1/me/devices",
            body: ["fcm_registration_token": fcmRegistrationToken]
        )
    }

    func apiTokens() async throws -> [APIToken] {
        let data = try await send(method: "GET", path: "/v1/me/apiTokens", body: nil)
        return try decode(APITokenListResponse.self, from: data).apiTokens
    }

    func issueAPIToken() async throws -> IssuedAPIToken {
        let data = try await send(method: "POST", path: "/v1/me/apiTokens", body: [:])
        return try decode(IssuedAPIToken.self, from: data)
    }

    func revokeAPIToken(id: String) async throws {
        _ = try await send(method: "DELETE", path: "/v1/me/apiTokens/\(Self.escaped(id))", body: nil)
    }

    /// Callable 関数のプロトコル (`{"data": ...}` を POST し、成功時は `{"result": ...}`、失敗時は `{"error": {"message": ...}}`) で呼ぶ。
    /// 削除対象は ID トークンの uid でサーバーが決めるため、パラメータは送らない。
    /// 成功の判定はステータスコードだけでなく `result` の中身で行う (プロキシ等が 200 を返しても、削除していないのに成功扱いにしない)
    func deleteAccount() async throws {
        let data = try await send(method: "POST", url: backend.deleteAccountURL, body: ["data": [String: String]()])
        _ = try decode(CallableResponse<DeleteAccountResult>.self, from: data).result
    }

    /// Callable 関数の成功応答
    private struct CallableResponse<Result: Decodable>: Decodable {
        let result: Result
    }

    /// `deleteAccount` の応答。削除した uid と、削除前にサーバーにデータが存在したか
    private struct DeleteAccountResult: Decodable {
        let userId: String
        let authUserExisted: Bool
        let userDocumentExisted: Bool
    }

    /// パスの 1 セグメントに埋め込める形へエスケープする。`/` も含めて escape し、URL 組み立て側では再エスケープしない
    /// (サーバーが採番する id に何が入るかはクライアントからは決められないため)
    static func escaped(_ pathComponent: String) -> String {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        return pathComponent.addingPercentEncoding(withAllowedCharacters: allowed) ?? pathComponent
    }

    /// 一覧の応答は将来 `nextCursor` 等が増えても壊れないようオブジェクトで受ける
    private struct APITokenListResponse: Decodable {
        let apiTokens: [APIToken]
    }

    /// サーバーのエラー応答。`error.message` をそのまま画面に出す
    private struct ErrorResponse: Decodable {
        struct Body: Decodable {
            let message: String
        }
        let error: Body
    }

    private func send(method: String, path: String, body: [String: Any]?) async throws -> Data {
        try await send(method: method, url: Self.url(baseURL: backend.baseURL, percentEncodedPath: path), body: body)
    }

    private func send(method: String, url: URL, body: [String: Any]?) async throws -> Data {
        guard let token = try await idToken() else { throw AlarmifyAPIError.notSignedIn }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AlarmifyAPIError.invalidResponse(detail: "Unexpected response: \(response)")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AlarmifyAPIError.server(statusCode: httpResponse.statusCode, message: Self.errorMessage(from: data))
        }
        return data
    }

    /// `path` はエスケープ済みのパスとして扱い、`appending(path:)` による二重エンコードを避ける
    private static func url(baseURL: URL, percentEncodedPath path: String) -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return baseURL }
        components.percentEncodedPath += path
        return components.url ?? baseURL
    }

    /// エラー本文は JSON の `error.message` を優先し、JSON でなければ body をそのまま使う
    private static func errorMessage(from data: Data) -> String {
        if let decoded = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
            return decoded.error.message
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw AlarmifyAPIError.invalidResponse(detail: error.localizedDescription)
        }
    }
}
