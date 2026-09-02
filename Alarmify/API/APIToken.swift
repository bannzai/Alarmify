import Foundation

/// バックエンドが発行した API トークン 1 件のメタデータ。
/// 平文の値はサーバーに保存されない (SHA-256 ハッシュと表示用プレフィックスだけを持つ) ため、
/// この型からは平文を復元できない。平文は発行直後の `IssuedAPIToken` にしか存在しない
struct APIToken: Identifiable, Equatable, Sendable, Decodable {
    let id: String
    /// 一覧でトークンを見分けるための先頭部分 (例: `alm_9f2c`)
    let prefix: String
    let createdAt: Date
    /// 外部サービスから最後に使われた日時。一度も使われていなければ nil
    let lastUsedAt: Date?
}

/// 発行直後にだけ手に入る、平文の値つきの API トークン。
/// `secret` は再取得できないため、この画面表示の 1 回でコピーしてもらう
struct IssuedAPIToken: Equatable, Sendable, Decodable {
    let token: APIToken
    /// 外部サービスの `Authorization: Bearer` に設定する平文の値
    let secret: String

    private enum CodingKeys: String, CodingKey {
        case token = "apiToken"
        case secret
    }
}

/// 発行したトークンをそのまま貼って使える `POST /v1/alarms` の curl の例。
/// 表示は 1 行に収める (ユーザーがコピーしてそのまま実行できるようにするため)
enum APITokenUsageExample {
    /// - Parameters:
    ///   - secret: 発行直後の平文トークン
    ///   - fireDate: 例に埋め込むアラームの発火日時
    ///   - title: 例に埋め込むアラームのタイトル。外部サービスから送る値のため翻訳対象にしない
    static func curl(secret: String, backend: AlarmifyBackend, fireDate: Date, title: String = "Deploy finished") -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let fireAt = formatter.string(from: fireDate)
        let body = "{\"fire_at\":\"\(fireAt)\",\"title\":\"\(title)\"}"
        return "curl -X POST \(backend.baseURL.absoluteString)/v1/alarms -H 'Authorization: Bearer \(secret)' -H 'Content-Type: application/json' -d '\(body)'"
    }
}
