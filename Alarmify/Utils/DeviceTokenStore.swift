import Foundation

/// APNs のデバイストークン (16 進文字列) の保存先。
/// バックエンドへの登録が実装されるまでの検証用に、画面表示とコピーができるよう App Group の UserDefaults に置く
enum DeviceTokenStore {
    private static let key = "apnsDeviceToken"

    static func save(_ token: String) {
        AppGroup.userDefaults.set(token, forKey: key)
    }

    static func load() -> String? {
        AppGroup.userDefaults.string(forKey: key)
    }
}
