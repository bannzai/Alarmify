import UserNotifications
import os

/// 検証方式 1 (Notification Service Extension) の入口。
/// APNs の visible push (`mutable-content: 1`) を受け、payload の alarm 指示を AlarmKit に反映してから通知を表示する
final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        let content = (request.content.mutableCopy() as? UNMutableNotificationContent) ?? UNMutableNotificationContent()
        bestAttemptContent = content

        guard let alarmRequest = AlarmRequest(userInfo: request.content.userInfo) else {
            contentHandler(content)
            return
        }
        Task {
            do {
                try await AlarmKitScheduler.apply(alarmRequest)
                // 検証中は通知本文に結果を出し、端末上で成否を目視できるようにする
                content.subtitle = "Alarm scheduled"
            } catch {
                Logger.push.error("Applying alarm request in Notification Service Extension failed: \(error.localizedDescription)")
                content.subtitle = "Alarm failed: \(error.localizedDescription)"
            }
            contentHandler(content)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler, let bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }
}
