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
            // ポートは firebase.json の emulators.functions.port と揃える。simulator からは 127.0.0.1 で Mac のローカルに届く
            return URL(string: "http://127.0.0.1:5410/demo-alarmify/asia-northeast1")!
        }
    }

    /// アプリ向け API のベース URL (HTTPS 関数 `appApi`)。Firebase Auth の ID トークンで認証する
    var appBaseURL: URL {
        functionsBaseURL.appending(path: "appApi")
    }

    /// 外部サービス向け API (`POST /v1/alarms` 等。Bearer = API トークン) のベース URL。
    /// Functions の `alarmsApi` (functions/src/index.ts) で、アプリ向けの `appBaseURL` とは別の関数として公開されている
    var alarmsAPIBaseURL: URL {
        functionsBaseURL.appending(path: "alarmsApi")
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
            return ("127.0.0.1", 9410)
        }
    }
}
