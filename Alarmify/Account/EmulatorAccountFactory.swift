#if DEBUG
import Foundation

/// 検証用に、ローカルの Auth エミュレータで匿名アカウントを作る。
/// 匿名認証の実装が入るまでアカウント削除フローを動かせないため、開発者メニューからだけ使う。
/// エミュレータ専用の経路のため DEBUG ビルドにだけ含める
enum EmulatorAccountFactory {
    static func signUpAnonymously() async throws -> AccountCredential {
        // Auth エミュレータは API キーを検証しないため、任意の値を渡す
        let url = BackendEndpoint.authEmulatorBaseURL
            .appending(path: "identitytoolkit.googleapis.com/v1/accounts:signUp")
            .appending(queryItems: [URLQueryItem(name: "key", value: "fake-api-key")])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["returnSecureToken": true])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let userId = json["localId"] as? String,
              let idToken = json["idToken"] as? String else {
            throw AccountDeletionError.invalidResponse
        }
        return AccountCredential(userId: userId, idToken: idToken)
    }
}
#endif
