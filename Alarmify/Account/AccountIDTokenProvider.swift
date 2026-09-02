import Foundation

/// 保存済みの認証情報から、有効な ID トークンを取得する。
/// ID トークンは約 1 時間で失効するため、保存した値を使い回さず API を呼ぶ直前に取得する
protocol AccountIDTokenProvider: Sendable {
    func idToken(for credential: AccountCredential) async throws -> String
}

/// Firebase Auth の secure token endpoint で refresh トークンを ID トークンに交換する。
/// 匿名認証 (アカウントの作成と Firebase Auth SDK の導入) が入るまで、実装があるのはエミュレータ経路だけになる
struct FirebaseIDTokenProvider: AccountIDTokenProvider {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func idToken(for credential: AccountCredential) async throws -> String {
#if DEBUG
        var request = URLRequest(url: BackendEndpoint.secureToken)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: credential.refreshToken),
        ]
        request.httpBody = components.percentEncodedQuery.map { Data($0.utf8) }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let idToken = json["id_token"] as? String else {
            throw AccountDeletionError.authenticationExpired
        }
        return idToken
#else
        // 匿名認証の実装で Firebase Auth SDK を入れるまで、アプリから ID トークンを取得する経路が無い
        throw AccountDeletionError.authenticationUnavailable
#endif
    }

}

/// 直前の試行で取得した ID トークンを保持する。
/// 削除がサーバーで成功して応答だけが届かなかった場合、そのアカウントの refresh トークンは以後使えなくなるため、
/// 取得し直せない再試行では前回のトークンを使う (ID トークンの有効期間内なら、冪等な削除をやり直せる)
actor CachingAccountIDTokenProvider: AccountIDTokenProvider {
    static let shared = CachingAccountIDTokenProvider()

    private let base: AccountIDTokenProvider
    private var idTokens: [String: String] = [:]

    init(base: AccountIDTokenProvider = FirebaseIDTokenProvider()) {
        self.base = base
    }

    func idToken(for credential: AccountCredential) async throws -> String {
        do {
            let idToken = try await base.idToken(for: credential)
            idTokens[credential.userId] = idToken
            return idToken
        } catch {
            guard let idToken = idTokens[credential.userId] else { throw error }
            return idToken
        }
    }
}
