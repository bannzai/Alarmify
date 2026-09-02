import Foundation
import Security
import os

/// バックエンドの API を呼ぶために必要なアカウントの認証情報。
/// 匿名認証の実装で発行して保存し、アカウント削除で破棄する
struct AccountCredential: Equatable, Sendable {
    /// Firebase Auth の uid。設定画面に表示する「アカウント ID」で、メールでの削除依頼にもこの値を使う
    let userId: String
    /// Firebase Auth の ID トークン。Functions の Callable へ Bearer トークンとして送る
    let idToken: String
}

/// アカウントの認証情報の保存先。
/// uid は秘匿情報ではないため App Group の UserDefaults に置き、bearer トークンとして使える ID トークンは Keychain に置く
enum AccountStore {
    private static let userIdKey = "accountUserId"
    private static let idTokenAccount = "accountIdToken"

    static func save(_ credential: AccountCredential) {
        AppGroup.userDefaults.set(credential.userId, forKey: userIdKey)
        Keychain.save(credential.idToken, account: idTokenAccount)
    }

    static func load() -> AccountCredential? {
        guard let userId = AppGroup.userDefaults.string(forKey: userIdKey),
              let idToken = Keychain.load(account: idTokenAccount) else {
            return nil
        }
        return AccountCredential(userId: userId, idToken: idToken)
    }

    /// 保存済みの認証情報を破棄する。保存されていない状態で呼んでも何も起きない
    static func clear() {
        AppGroup.userDefaults.removeObject(forKey: userIdKey)
        Keychain.delete(account: idTokenAccount)
    }
}

/// Keychain (この端末のこのアプリ限定) に文字列を保存する。
/// push の受信中 (端末ロック中) にも読めるよう、アクセス条件は初回アンロック以降にする
private enum Keychain {
    private static let service = "com.bannzai.Alarmify.account"

    static func save(_ value: String, account: String) {
        delete(account: account)
        var attributes = query(account: account)
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            Logger.account.error("Saving \(account, privacy: .public) to Keychain failed with status \(status)")
        }
    }

    static func load(account: String) -> String? {
        var attributes = query(account: account)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &item)
        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                Logger.account.error("Loading \(account, privacy: .public) from Keychain failed with status \(status)")
            }
            return nil
        }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let status = SecItemDelete(query(account: account) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            Logger.account.error("Deleting \(account, privacy: .public) from Keychain failed with status \(status)")
        }
    }

    private static func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
