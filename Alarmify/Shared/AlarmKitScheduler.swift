import AlarmKit
import SwiftUI

/// AlarmKit への登録・取消。app 本体と Notification Service Extension の両方から同じ経路で呼ぶ
enum AlarmKitScheduler {
    static var authorizationState: AlarmManager.AuthorizationState {
        AlarmManager.shared.authorizationState
    }

    static func requestAuthorization() async throws -> AlarmManager.AuthorizationState {
        try await AlarmManager.shared.requestAuthorization()
    }

    /// 登録済みアラーム。取得に失敗した場合は空 (表示用途のため例外にしない)
    static var alarms: [Alarm] {
        (try? AlarmManager.shared.alarms) ?? []
    }

    /// AlarmRequest を AlarmKit に反映する。同じ id の再 schedule は登録し直し (取消 → 登録) で上書きするため、同じ指示の再送は冪等
    static func apply(_ request: AlarmRequest) async throws {
        switch request.action {
        case .schedule:
            guard let fireDate = request.fireDate else { return }
            try await schedule(id: request.id, fireDate: fireDate, title: request.title ?? "Alarmify")
        case .cancel:
            try cancel(id: request.id)
        }
    }

    /// 固定日時のアラームを登録する。同じ id が登録済みなら取り消してから登録する
    static func schedule(id: UUID, fireDate: Date, title: String) async throws {
        let attributes = AlarmAttributes<AlarmifyAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert(title: title)),
            metadata: AlarmifyAlarmMetadata(title: title),
            tintColor: .orange
        )
        try? AlarmManager.shared.cancel(id: id)
        _ = try await AlarmManager.shared.schedule(
            id: id,
            configuration: .alarm(
                schedule: .fixed(fireDate),
                attributes: attributes,
                sound: .default
            )
        )
    }

    static func cancel(id: UUID) throws {
        try AlarmManager.shared.cancel(id: id)
    }

    /// 発火画面の alert を作成する。
    /// stopButton を渡さない init は iOS 26.1 以降にしか存在しないため、iOS 26.0 のみ stopButton 付きの init へフォールバックする
    /// (iOS 26.1 以降では指定した stopButton は使われず、停止 UI はシステム標準描画になる)
    private static func alert(title: String) -> AlarmPresentation.Alert {
        let resource = LocalizedStringResource(String.LocalizationValue(title))
        if #available(iOS 26.1, *) {
            return .init(title: resource)
        } else {
            // ja: 止める
            return .init(title: resource, stopButton: .init(text: "Stop", textColor: .white, systemImageName: "stop.circle"))
        }
    }
}
