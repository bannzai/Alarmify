import Foundation

/// アプリ・外部サービスから見た Alarmify バックエンド (Cloud Functions gen2) の接続先。
/// production は Firebase プロジェクト `alarmify-prod`、emulator は手元の Firebase Emulator Suite (`demo-alarmify`) を指す。
/// アプリ向け (`appApi`) と外部サービス向け (`alarmsApi`) は別の HTTPS 関数のため、ベース URL も分けて持つ
enum AlarmifyBackend: String, CaseIterable, Sendable {
    case production
    case emulator

    /// アプリ向け API (`appApi`) のベース URL。Firebase Auth の ID トークンで認証する
    var appBaseURL: URL {
        functionURL(name: "appApi")
    }

    /// 外部サービス向け API (`alarmsApi`) のベース URL。API トークンを `Authorization: Bearer` に設定して呼ぶ
    var alarmsBaseURL: URL {
        functionURL(name: "alarmsApi")
    }

    /// Firebase Auth エミュレータのホストとポート。production では nil
    var authEmulator: (host: String, port: Int)? {
        switch self {
        case .production:
            return nil
        case .emulator:
            return ("127.0.0.1", 9410)
        }
    }

    private func functionURL(name: String) -> URL {
        switch self {
        case .production:
            // Cloud Functions gen2 の HTTPS 関数 (asia-northeast1)
            return URL(string: "https://asia-northeast1-alarmify-prod.cloudfunctions.net/\(name)")!
        case .emulator:
            // ポートは firebase.json の emulators 設定に合わせる。simulator からは 127.0.0.1 で Mac のローカルに届く
            return URL(string: "http://127.0.0.1:5410/demo-alarmify/asia-northeast1/\(name)")!
        }
    }
}
