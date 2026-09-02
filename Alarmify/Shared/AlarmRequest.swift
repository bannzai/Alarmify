import Foundation

/// サーバーからの push に含まれる、AlarmKit へ反映する 1 件のアラーム指示。
/// push payload の `alarm` キー配下の JSON を表す。schedule は fire_at 必須、cancel は id だけで足りる
///
/// ```json
/// { "alarm": { "id": "<UUID>", "action": "schedule", "fire_at": "2026-09-03T07:00:00Z", "title": "Deploy finished" } }
/// ```
struct AlarmRequest: Equatable, Sendable {
    enum Action: String, Sendable {
        case schedule
        case cancel
    }

    static let payloadKey = "alarm"

    var id: UUID
    var action: Action
    /// schedule の発火日時 (ISO 8601 の `fire_at`)。cancel では nil
    var fireDate: Date?
    var title: String?

    /// push の userInfo 全体から生成する。`alarm` キーが無い・形式不正なら nil
    init?(userInfo: [AnyHashable: Any]) {
        guard let payload = userInfo[Self.payloadKey] as? [String: Any] else { return nil }
        self.init(payload: payload)
    }

    /// `alarm` キー配下の辞書から生成する。必須項目の欠落・型不一致・日時の形式不正は nil
    init?(payload: [String: Any]) {
        guard let idString = payload["id"] as? String, let id = UUID(uuidString: idString) else { return nil }
        guard let actionString = payload["action"] as? String, let action = Action(rawValue: actionString) else { return nil }
        var fireDate: Date?
        if let fireAt = payload["fire_at"] {
            guard let fireAtString = fireAt as? String, let date = ISO8601DateFormatter().date(from: fireAtString) else { return nil }
            fireDate = date
        }
        if action == .schedule && fireDate == nil { return nil }
        self.id = id
        self.action = action
        self.fireDate = fireDate
        self.title = payload["title"] as? String
    }
}
