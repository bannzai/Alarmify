import Foundation

/// アプリ向け API `GET /v1/alarms` が返すアラーム履歴の 1 件 (`users/{uid}/alarms/{alarmId}` の内容)。
/// 外部サービスからの登録・取り消しと、その配送結果、端末側の反映結果をまとめて持つ
struct AlarmHistoryEntry: Identifiable, Equatable, Sendable, Decodable {
    /// サーバー上のアラームの状態。発火したかどうかはサーバーでは分からないため、発火時刻の経過は使用側 (View) が判定する
    enum Status: String, Decodable, Sendable {
        case scheduled
        case canceled
    }

    /// 登録済みの端末への push の配送結果
    struct Delivery: Equatable, Sendable, Decodable {
        let successCount: Int
        let failureCount: Int

        private enum CodingKeys: String, CodingKey {
            case successCount = "success_count"
            case failureCount = "failure_count"
        }
    }

    /// 端末が AlarmKit へ反映した結果 (端末ごとに最新の 1 件)
    struct DeviceReport: Equatable, Sendable, Decodable {
        let deviceID: String
        let action: AlarmRequest.Action
        let result: AlarmApplyReport.Result
        let error: String?
        let occurredAt: Date

        private enum CodingKeys: String, CodingKey {
            case deviceID = "device_id"
            case action
            case result
            case error
            case occurredAt = "occurred_at"
        }
    }

    /// アラームの id (小文字の UUID)。AlarmKit 側の UUID と比べる時は `UUID(uuidString:)` で揃える
    let id: String
    let status: Status
    /// 外部サービスが送ったタイトル。送られていなければ nil
    let title: String?
    let fireAt: Date
    let createdAt: Date
    /// 登録を行った API トークンの id
    let tokenID: String
    /// 配送結果。`delivery` を返さない古いバックエンド (このフィールドを追加する前のデプロイ) からの応答では nil
    let delivery: Delivery?
    /// 端末側の反映結果。返さない古いバックエンドからの応答では空
    let deviceReports: [DeviceReport]

    /// この端末 (`deviceID`) からの反映結果
    func deviceReport(deviceID: String) -> DeviceReport? {
        deviceReports.first { $0.deviceID == deviceID }
    }
}

extension AlarmHistoryEntry {
    private enum CodingKeys: String, CodingKey {
        case id
        case status
        case title
        case fireAt = "fire_at"
        case createdAt = "created_at"
        case tokenID = "token_id"
        case delivery
        case deviceReports = "device_reports"
    }

    /// `delivery` と `device_reports` はアプリ側で先に必須にするとバックエンドのデプロイ順に縛られるため、無い応答も受け付ける
    /// (無い時に値をでっち上げるのではなく「不明」として扱う。extension に置くのは memberwise init を残すため)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        status = try container.decode(Status.self, forKey: .status)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        fireAt = try container.decode(Date.self, forKey: .fireAt)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        tokenID = try container.decode(String.self, forKey: .tokenID)
        delivery = try container.decodeIfPresent(Delivery.self, forKey: .delivery)
        deviceReports = try container.decodeIfPresent([DeviceReport].self, forKey: .deviceReports) ?? []
    }
}
