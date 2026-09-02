import Foundation

/// アプリ・外部サービスから見た Alarmify バックエンド (Cloud Functions gen2) の接続先。
/// production は Firebase プロジェクト `alarmify-prod`、emulator は手元の Firebase Emulator Suite (`demo-alarmify`) を指す
enum AlarmifyBackend: String, CaseIterable, Sendable {
    case production
    case emulator

    /// API のベース URL。アプリ向け・外部サービス向けのどちらのパスもこの下にある
    var baseURL: URL {
        switch self {
        case .production:
            // Cloud Functions gen2 の HTTPS 関数 `api` (asia-northeast1)
            return URL(string: "https://asia-northeast1-alarmify-prod.cloudfunctions.net/api")!
        case .emulator:
            // Functions エミュレータの既定ポート。simulator からは 127.0.0.1 で Mac のローカルに届く
            return URL(string: "http://127.0.0.1:5001/demo-alarmify/asia-northeast1/api")!
        }
    }

    /// 外部サービス向け API (`POST /v1/alarms` 等。Bearer = API トークン) のベース URL。
    /// Functions の `alarmsApi` (functions/src/index.ts) で、アプリ向けの `baseURL` とは別の関数として公開されている
    var alarmsAPIBaseURL: URL {
        switch self {
        case .production:
            return URL(string: "https://asia-northeast1-alarmify-prod.cloudfunctions.net/alarmsApi")!
        case .emulator:
            // Functions エミュレータのポートは firebase.json の emulators.functions.port
            return URL(string: "http://127.0.0.1:5410/demo-alarmify/asia-northeast1/alarmsApi")!
        }
    }

    /// Firebase Auth エミュレータのホストとポート。production では nil
    var authEmulator: (host: String, port: Int)? {
        switch self {
        case .production:
            return nil
        case .emulator:
            return ("127.0.0.1", 9099)
        }
    }
}
