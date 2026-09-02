import Foundation
import Security
import UIKit

/// バックエンドへ端末を登録する時の `device_id` (`POST /v1/devices`)。
/// 同じ端末からの再登録が上書きになるよう、一度決めた値を返し続ける
enum DeviceIdentifier {
    private static let service = "com.bannzai.Alarmify.deviceIdentifier"
    private static let account = "deviceIdentifier"

    /// この端末の識別子。初回に解決した値を keychain に保存し、以降はそれを返す (冪等)。
    ///
    /// 保存先を keychain にするのは、匿名認証のアカウント (Firebase Auth の keychain 永続化) と
    /// 寿命を揃えるため。App Group の UserDefaults はアプリの削除で消えるため、アカウントだけが残る再インストールで
    /// 端末登録が新しい device_id として増え、古い登録 (死んだ FCM トークン) が端末数の上限を食い潰す。
    /// `identifierForVendor` も同じ vendor のアプリを全て削除すると変わるため、識別子そのものの永続化で担保する。
    /// keychain を扱えない構成 (署名なしのビルド等) では App Group の UserDefaults へ退避する
    static var current: String {
        if let saved = loadFromKeychain() {
            return saved
        }
        if let saved = AppGroup.userDefaults.string(forKey: account), !saved.isEmpty {
            return saved
        }
        let identifier = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        if !saveToKeychain(identifier) {
            AppGroup.userDefaults.set(identifier, forKey: account)
        }
        return identifier
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func loadFromKeychain() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let identifier = String(data: data, encoding: .utf8),
              !identifier.isEmpty
        else {
            return nil
        }
        return identifier
    }

    private static func saveToKeychain(_ identifier: String) -> Bool {
        var attributes = baseQuery
        attributes[kSecValueData as String] = Data(identifier.utf8)
        // push を受けた時に Extension からも読めるよう、初回のロック解除以降は取り出せるようにする。
        // ThisDeviceOnly にするのは、この値が「配送先のこの端末」を指すため。バックアップ復元や機種変更で
        // 別の端末へ移ると、同じ device_id の登録を互いに上書きし合って片方に push が届かなくなる
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            return SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: Data(identifier.utf8)] as CFDictionary) == errSecSuccess
        }
        return status == errSecSuccess
    }
}
