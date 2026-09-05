import Foundation

/// 開発者メニューから push payload を AlarmKit へ適用する検証操作 (`.claude/rules/debug-menu-for-verification.md`)。
/// simulator では `xcrun simctl push` の visible push が Notification Service Extension を経由せず、background push は破棄されるため、
/// push 受信時と同じ経路 (`AlarmRequest(userInfo:)` → `AlarmKitScheduler.apply`) をアプリ内から流して検証する
enum DebugPushPayload {
    enum Error: Swift.Error, LocalizedError {
        /// App Store 配布 (開発者メニューが解放されていない) では何もしない
        case unavailable
        /// 組み立てた userInfo を AlarmRequest に変換できなかった
        case invalidPayload

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "The developer menu is not available in this build."
            case .invalidPayload:
                return "The push payload could not be parsed as an alarm request."
            }
        }
    }

    /// 適用するアラームの id。`documents/push-payloads/*.apns` と同じ固定 UUID にし、再実行は同じ id の登録し直しになる (冪等)
    static let alarmID = UUID(uuidString: "3B0E0C6E-9F1B-4C0A-9E7D-1F2A3B4C5D6E")!
    /// schedule の既定の発火までの秒数。AlarmKit の発火 UI を短い待ち時間で確認できる 1〜2 分後にする
    static let defaultFireInterval: TimeInterval = 90
    /// アラームの表示名。外部サービスが送る `title` に相当し、ローカライズしない
    static let title = "Developer menu push"

    /// `documents/push-payloads/schedule.apns` と同じ形の userInfo。`fire_at` は AlarmRequest が読む ISO 8601 (秒精度・UTC)
    static func scheduleUserInfo(fireDate: Date) -> [AnyHashable: Any] {
        userInfo(alarm: [
            "id": alarmID.uuidString,
            "action": AlarmRequest.Action.schedule.rawValue,
            "fire_at": ISO8601DateFormatter().string(from: fireDate),
            "title": title,
        ])
    }

    /// `documents/push-payloads/cancel.apns` と同じ形の userInfo
    static func cancelUserInfo() -> [AnyHashable: Any] {
        userInfo(alarm: [
            "id": alarmID.uuidString,
            "action": AlarmRequest.Action.cancel.rawValue,
        ])
    }

    /// push 受信時と同じ経路で userInfo を AlarmKit に反映し、適用した AlarmRequest を返す。
    /// 開発者メニューが解放されていない配布では AlarmKit に触れない
    @discardableResult
    static func apply(userInfo: [AnyHashable: Any]) async throws -> AlarmRequest {
        guard DeveloperMenu.isAvailable else { throw Error.unavailable }
        guard let request = AlarmRequest(userInfo: userInfo) else { throw Error.invalidPayload }
        try await AlarmKitScheduler.apply(request)
        return request
    }

    private static func userInfo(alarm: [String: Any]) -> [AnyHashable: Any] {
        [
            "aps": [
                "alert": ["title": "Signalarm", "body": title],
                "mutable-content": 1,
            ],
            AlarmRequest.payloadKey: alarm,
        ]
    }
}
