import Foundation

/// バックエンドが発行した API トークン 1 件のメタデータ。
/// 平文の値はサーバーに保存されない (SHA-256 ハッシュと表示用プレフィックスだけを持つ) ため、
/// この型からは平文を復元できない。平文は発行直後の `IssuedAPIToken` にしか存在しない
struct APIToken: Identifiable, Equatable, Sendable, Decodable {
    let id: String
    /// 発行時に付ける、サービス名などの表示用の名前 (省略時はサーバー側の既定値 `default`)
    let name: String
    /// 一覧でトークンを見分けるための先頭部分 (例: `alm_9f2c`)
    let prefix: String
    let createdAt: Date
    /// 外部サービスから最後に使われた日時。一度も使われていなければ nil
    let lastUsedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case prefix
        case createdAt = "created_at"
        case lastUsedAt = "last_used_at"
    }
}

/// 発行直後にだけ手に入る、平文の値つきの API トークン。
/// `secret` は再取得できないため、この画面表示の 1 回でコピーしてもらう。
/// `POST /v1/api-tokens` の応答は入れ子のないオブジェクトのため、メタデータと平文へ分けて受け取る
struct IssuedAPIToken: Equatable, Sendable, Decodable {
    let token: APIToken
    /// 外部サービスの `Authorization: Bearer` に設定する平文の値
    let secret: String

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case prefix
        case createdAt = "created_at"
        /// 応答の `token` は平文の値。トークンのメタデータではない
        case secret = "token"
    }

    init(token: APIToken, secret: String) {
        self.token = token
        self.secret = secret
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // 発行直後は一度も使われていないため lastUsedAt は nil (応答にも含まれない)
        token = APIToken(
            id: try container.decode(String.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            prefix: try container.decode(String.self, forKey: .prefix),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            lastUsedAt: nil
        )
        secret = try container.decode(String.self, forKey: .secret)
    }
}

/// 発行したトークンをそのまま貼って使える `POST /v1/alarms` の curl の例。
/// 宛先は外部サービス向け API (`alarmsApi`)。表示は 1 行に収める (ユーザーがコピーしてそのまま実行できるようにするため)
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
        return "curl -X POST \(backend.alarmsBaseURL.absoluteString)/v1/alarms -H 'Authorization: Bearer \(secret)' -H 'Content-Type: application/json' -d '\(body)'"
    }
}
