import Foundation

/// 端末のトークンの保存先。画面表示とコピーができるよう App Group の UserDefaults に置く。
/// APNs のデバイストークンは push 経路の検証用、FCM の登録トークンはバックエンドへ登録する配送先
enum DeviceTokenStore {
    private static let apnsKey = "apnsDeviceToken"
    private static let fcmKey = "fcmRegistrationToken"

    static func save(_ token: String) {
        AppGroup.userDefaults.set(token, forKey: apnsKey)
    }

    static func load() -> String? {
        AppGroup.userDefaults.string(forKey: apnsKey)
    }

    static func saveFCMRegistrationToken(_ token: String) {
        AppGroup.userDefaults.set(token, forKey: fcmKey)
    }

    static func loadFCMRegistrationToken() -> String? {
        AppGroup.userDefaults.string(forKey: fcmKey)
    }
}
