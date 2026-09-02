import Foundation

/// バックエンド (Cloud Functions gen2 / asia-northeast1) のエンドポイント。
/// DEBUG ビルドはローカルの Firebase Emulator を向く (ポートは `firebase.json` と揃える)
enum BackendEndpoint {
#if DEBUG
    static let functionsBaseURL = URL(string: "http://127.0.0.1:5501/demo-alarmify/asia-northeast1")!
    /// Auth エミュレータ。検証用の匿名アカウント作成 (開発者メニュー) だけで使う
    static let authEmulatorBaseURL = URL(string: "http://127.0.0.1:9399")!
#else
    static let functionsBaseURL = URL(string: "https://asia-northeast1-alarmify-prod.cloudfunctions.net")!
#endif

    /// アカウント削除の Callable
    static var deleteAccount: URL { functionsBaseURL.appending(path: "deleteAccount") }
}
