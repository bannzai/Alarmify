import Foundation

/// アプリ・外部サービスから見た Alarmify バックエンド (Cloud Functions gen2) の接続先。
/// production は Firebase プロジェクト `alarmify-prod`、emulator は手元の Firebase Emulator Suite (`demo-alarmify`) を指す
enum AlarmifyBackend: String, CaseIterable, Sendable {
    case production
    case emulator

    /// Cloud Functions (asia-northeast1) のルート。各関数はこの直下に並ぶ
    var functionsBaseURL: URL {
        switch self {
        case .production:
            return URL(string: "https://asia-northeast1-alarmify-prod.cloudfunctions.net")!
        case .emulator:
            // ポートは firebase.json の emulators.functions と揃える。simulator からは 127.0.0.1 で Mac のローカルに届く
            return URL(string: "http://127.0.0.1:5501/demo-alarmify/asia-northeast1")!
        }
    }

    /// API のベース URL (HTTPS 関数 `api`)。アプリ向け・外部サービス向けのどちらのパスもこの下にある
    var baseURL: URL {
        functionsBaseURL.appending(path: "api")
    }

    /// アカウント削除の Callable 関数 `deleteAccount`
    var deleteAccountURL: URL {
        functionsBaseURL.appending(path: "deleteAccount")
    }

    /// Firebase Auth エミュレータのホストとポート (firebase.json の emulators.auth と揃える)。production では nil
    var authEmulator: (host: String, port: Int)? {
        switch self {
        case .production:
            return nil
        case .emulator:
            return ("127.0.0.1", 9399)
        }
    }
}
