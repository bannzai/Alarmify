import Foundation

/// バックエンド (Cloud Functions gen2 / asia-northeast1) のエンドポイント。
/// DEBUG ビルドはローカルの Firebase Emulator を向く (ポートは `firebase.json` と揃える)
enum BackendEndpoint {
#if DEBUG
    static let functionsBaseURL = URL(string: "http://127.0.0.1:5501/demo-alarmify/asia-northeast1")!
    /// Auth エミュレータ。検証用の匿名アカウント作成 (開発者メニュー) と ID トークンの取得で使う。
    /// エミュレータは API キーを検証しないため、キーには任意の値を渡す
    static let authEmulatorBaseURL = URL(string: "http://127.0.0.1:9399")!

    /// refresh トークンを ID トークンに交換する endpoint
    static var secureToken: URL {
        authEmulatorBaseURL
            .appending(path: "securetoken.googleapis.com/v1/token")
            .appending(queryItems: [URLQueryItem(name: "key", value: "fake-api-key")])
    }
#else
    static let functionsBaseURL = URL(string: "https://asia-northeast1-alarmify-prod.cloudfunctions.net")!
#endif

    /// アカウント削除の Callable
    static var deleteAccount: URL { functionsBaseURL.appending(path: "deleteAccount") }
}
