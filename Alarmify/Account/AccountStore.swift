import Foundation

/// バックエンドの API を呼ぶために必要なアカウントの認証情報。
/// 匿名認証の実装で発行して保存し、アカウント削除で破棄する
struct AccountCredential: Equatable, Sendable {
    /// Firebase Auth の uid。設定画面に表示する「アカウント ID」で、メールでの削除依頼にもこの値を使う
    let userId: String
    /// Firebase Auth の ID トークン。Functions の Callable へ Bearer トークンとして送る
    let idToken: String
}

/// アカウントの認証情報の保存先。Extension からも参照できるよう App Group の UserDefaults に置く
enum AccountStore {
    private static let userIdKey = "accountUserId"
    private static let idTokenKey = "accountIdToken"

    static func save(_ credential: AccountCredential) {
        AppGroup.userDefaults.set(credential.userId, forKey: userIdKey)
        AppGroup.userDefaults.set(credential.idToken, forKey: idTokenKey)
    }

    static func load() -> AccountCredential? {
        guard let userId = AppGroup.userDefaults.string(forKey: userIdKey),
              let idToken = AppGroup.userDefaults.string(forKey: idTokenKey) else {
            return nil
        }
        return AccountCredential(userId: userId, idToken: idToken)
    }

    /// 保存済みの認証情報を破棄する。保存されていない状態で呼んでも何も起きない
    static func clear() {
        AppGroup.userDefaults.removeObject(forKey: userIdKey)
        AppGroup.userDefaults.removeObject(forKey: idTokenKey)
    }
}
