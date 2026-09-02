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
        // トークン id はサーバーが採番した識別子だが、URL に載せる前にパーセントエンコードする
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        _ = try await send(method: "DELETE", path: "/v1/me/apiTokens/\(encoded)", body: nil)
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

    private func send(method: String, path: String, body: [String: String]?) async throws -> Data {
        guard let token = try await idToken() else { throw AlarmifyAPIError.notSignedIn }

        var request = URLRequest(url: backend.baseURL.appending(path: path))
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
