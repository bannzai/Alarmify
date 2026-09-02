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

    /// 保存済みのトークンを破棄する。アカウント削除でサーバー上の端末情報が消えた後、アプリを初期状態に戻すために使う。
    /// 保存されていない状態で呼んでも何も起きない
    static func clear() {
        AppGroup.userDefaults.removeObject(forKey: key)
    }
}
