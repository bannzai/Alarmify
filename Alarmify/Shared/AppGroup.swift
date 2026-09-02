import Foundation

/// app 本体と Extension (Notification Service / Widget) が共有する App Group
enum AppGroup {
    static let identifier = "group.com.bannzai.Alarmify"

    /// App Group の UserDefaults。suite が解決できない構成 (entitlements 不足) は設定ミスのため standard へ黙って倒さない
    static var userDefaults: UserDefaults {
        guard let userDefaults = UserDefaults(suiteName: identifier) else {
            fatalError("App Group \(identifier) is not available. Check the application-groups entitlement of every target")
        }
        return userDefaults
    }
}
