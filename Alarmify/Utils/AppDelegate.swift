import UIKit
import UserNotifications
import os

/// APNs への登録と push 受信の入口。SwiftUI の App からは UIApplicationDelegateAdaptor で接続する
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // visible push (検証方式 1) の表示許可。許可の有無に関わらずデバイストークンは取得できる
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                Logger.push.error("Notification authorization failed: \(error.localizedDescription)")
            }
        }
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        DeviceTokenStore.save(deviceToken.map { String(format: "%02x", $0) }.joined())
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Logger.push.error("APNs registration failed: \(error.localizedDescription)")
    }

    /// Background push (`content-available: 1`) の受信。検証方式 2 (Silent / Background Push) の入口。
    /// userInfo は non-Sendable のため main actor へ送れず、nonisolated で受けて Sendable な AlarmRequest に変換してから処理する
    nonisolated func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        guard let request = AlarmRequest(userInfo: userInfo) else { return .noData }
        do {
            try await AlarmKitScheduler.apply(request)
            return .newData
        } catch {
            Logger.push.error("Applying alarm request from background push failed: \(error.localizedDescription)")
            return .failed
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// foreground 中も push を表示し、検証時に到着を目視できるようにする
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
