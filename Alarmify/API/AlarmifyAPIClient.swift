import Foundation

/// アプリ向けバックエンド API (`appApi`) の呼び出し口。
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

/// URLSession で Cloud Functions のアプリ向け API (`appApi`) を叩く実装。
/// Firebase Auth の ID トークンを `Authorization: Bearer` に付けて認証する。
/// Firebase への依存は `idToken` クロージャに閉じ込め、テストでは差し替える
struct URLSessionAlarmifyAPIClient: AlarmifyAPIClient {
    let backend: AlarmifyBackend
    let session: URLSession
    /// 端末登録の宛先を識別する値。同じ値での再登録は上書きになる
    let deviceID: String
    /// Firebase Auth の ID トークンを返す。未サインインなら nil
    let idToken: @Sendable () async throws -> String?

    init(
        backend: AlarmifyBackend,
        session: URLSession = .shared,
        deviceID: String = DeviceIdentifier.current,
        idToken: @escaping @Sendable () async throws -> String?
    ) {
        self.backend = backend
        self.session = session
        self.deviceID = deviceID
        self.idToken = idToken
    }

    func registerDevice(fcmRegistrationToken: String) async throws {
        _ = try await send(
            method: "POST",
            path: "/v1/devices",
            body: ["device_id": deviceID, "fcm_token": fcmRegistrationToken, "platform": "ios"]
        )
    }

    /// 一覧は 1 ページに収まらないことがある (Pro プランのトークン数に上限が無い)。
    /// 途中で打ち切ると古いトークンが画面から消え、漏洩を疑った時に失効させられなくなるため、cursor を辿って全ページ取得する
    func apiTokens() async throws -> [APIToken] {
        var tokens: [APIToken] = []
        var cursor: String?
        repeat {
            // 1 ページあたりの件数はサーバーが受け付ける最大値 (alarmHistoryLimitSchema の max)。往復を最小にする
            var query = [URLQueryItem(name: "limit", value: "100")]
            if let cursor {
                query.append(URLQueryItem(name: "cursor", value: cursor))
            }
            let data = try await send(method: "GET", path: "/v1/api-tokens", query: query, body: nil)
            let page = try decode(APITokenListResponse.self, from: data)
            tokens += page.apiTokens
            // 同じ cursor が返り続ける応答で無限ループにしない
            guard let nextCursor = page.nextCursor, nextCursor != cursor else { break }
            cursor = nextCursor
        } while true
        return tokens
    }

    func issueAPIToken() async throws -> IssuedAPIToken {
        // name を送らない発行はサーバー側の既定値 (`default`) になる
        let data = try await send(method: "POST", path: "/v1/api-tokens", body: [:])
        return try decode(IssuedAPIToken.self, from: data)
    }

    func revokeAPIToken(id: String) async throws {
        _ = try await send(method: "DELETE", path: "/v1/api-tokens/\(Self.escaped(id))", body: nil)
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

    /// 一覧の応答。`nextCursor` は続きのページを指し、最後のページでは nil になる
    private struct APITokenListResponse: Decodable {
        let apiTokens: [APIToken]
        let nextCursor: String?

        private enum CodingKeys: String, CodingKey {
            case apiTokens = "api_tokens"
            case nextCursor = "next_cursor"
        }
    }

    /// サーバーのエラー応答。`error.message` をそのまま画面に出し、`error.code` で分岐する
    /// (Callable 関数のエラーは `code` の代わりに `status` を持つため、`code` は無くても受け付ける)
    private struct ErrorResponse: Decodable {
        struct Body: Decodable {
            let code: String?
            let message: String
        }
        let error: Body
    }

    private func send(method: String, path: String, query: [URLQueryItem]? = nil, body: [String: Any]?) async throws -> Data {
        try await send(method: method, url: Self.url(baseURL: backend.appBaseURL, percentEncodedPath: path, query: query), body: body)
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
            let error = Self.errorBody(from: data)
            throw AlarmifyAPIError.server(statusCode: httpResponse.statusCode, code: error.code, message: error.message)
        }
        return data
    }

    /// `path` はエスケープ済みのパスとして扱い、`appending(path:)` による二重エンコードを避ける
    private static func url(baseURL: URL, percentEncodedPath path: String, query: [URLQueryItem]?) -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return baseURL }
        components.percentEncodedPath += path
        components.queryItems = query
        return components.url ?? baseURL
    }

    /// エラー本文は JSON の `error.code` / `error.message` を優先し、JSON でなければ body をそのままメッセージにする
    private static func errorBody(from data: Data) -> (code: String?, message: String) {
        if let decoded = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
            return (decoded.error.code, decoded.error.message)
        }
        return (nil, String(data: data, encoding: .utf8) ?? "")
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try Self.decoder.decode(type, from: data)
        } catch {
            throw AlarmifyAPIError.invalidResponse(detail: error.localizedDescription)
        }
    }

    /// バックエンドの日時は `Date.toISOString()` (小数秒つき) で返るが、Firestore から読み直した値など小数秒が無い形も届く。
    /// `.iso8601` は小数秒を解釈できないため、両方を受け付ける
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let withFractionalSeconds = ISO8601DateFormatter()
        withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let withoutFractionalSeconds = ISO8601DateFormatter()
        withoutFractionalSeconds.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = withFractionalSeconds.date(from: text) ?? withoutFractionalSeconds.date(from: text) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Not an ISO 8601 date: \(text)")
                )
            }
            return date
        }
        return decoder
    }()
}
