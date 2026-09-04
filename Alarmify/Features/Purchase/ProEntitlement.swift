import Foundation
import RevenueCat
import os

extension String {
    /// RevenueCat の entitlement 判定結果をキャッシュする UserDefaults キー。
    /// View 外 (push 受信後の処理など) から同期的に参照するため、customerInfoStream の更新をここへ保存する
    static let proEntitlementActive = "proEntitlementActive"
    /// entitlement の失効日時 (epoch 秒) をキャッシュする UserDefaults キー。
    /// 購読はアプリ停止中に失効し得るため、proEntitlementActive と対で保存して参照時に同期判定する。
    /// 請求猶予期間中はその終了日時 (RevenueCat の SubscriptionInfo.gracePeriodExpiresDate) を保存する
    static let proEntitlementExpiration = "proEntitlementExpiration"
}

/// キャッシュへ保存する実効的な失効日時。
/// 購読が請求猶予期間にある間は entitlement の expirationDate を過ぎてもアクセスが続くため、
/// 猶予期間の終了日時が後ならそちらを失効日時として扱う (ストアが正を持つ境界をそのまま使う。PR #20 レビュー指摘)。
/// どちらも無ければ買い切りまたは未購入として nil。純粋関数であり冪等
func effectiveExpirationDate(expirationDate: Date?, gracePeriodExpiresDate: Date?) -> Date? {
    switch (expirationDate, gracePeriodExpiresDate) {
    case (nil, nil):
        return nil
    case (let expirationDate?, nil):
        return expirationDate
    case (nil, let gracePeriodExpiresDate?):
        return gracePeriodExpiresDate
    case (let expirationDate?, let gracePeriodExpiresDate?):
        return max(expirationDate, gracePeriodExpiresDate)
    }
}

/// キャッシュした課金判定が now 時点でも有効か。
/// 失効日時 (猶予期間があればその終了日時) が保存されている場合は同期比較し、
/// 期限切れ・返金がアプリ停止中に起きても古い true を返さないようにする。
/// 失効日時なしは買い切りまたは未購入で、active の値をそのまま使う。
/// 純粋関数であり、同じ入力に対して常に同じ出力を返す (冪等)
func cachedProActive(active: Bool, expirationDate: Date?, now: Date) -> Bool {
    guard active else { return false }
    guard let expirationDate else { return true }
    return expirationDate > now
}

/// Pro プランの課金判定と RevenueCat SDK の初期化 (課金設計は documents/PROJECT.md 参照)
enum ProEntitlement {
    /// RevenueCat の entitlement 識別子。RevenueCat へ登録する entitlement の lookup_key と一致させる
    static let entitlementIdentifier = "pro"

    /// ペイウォールが表示する offering の識別子。RevenueCat へ登録する offering の lookup_key と一致させる
    static let offeringIdentifier = "default"

    /// RevenueCat の iOS 用 public API key。
    /// public リポジトリのためソースに実値を置かず、Config.xcconfig / Config.local.xcconfig から
    /// Info.plist 経由で受け取る (手順は Config.xcconfig のコメント参照)。
    /// キーを持たない環境では空文字になり configure をスキップする
    static let revenueCatAPIKey = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String ?? ""

    /// 現在のユーザーが Pro かどうか。
    /// customerInfoStream が UserDefaults へ保存した最新の entitlement 判定を、失効日時と突き合わせて返す
    static var isPro: Bool {
        cachedProActive(
            active: UserDefaults.standard.bool(forKey: .proEntitlementActive),
            expirationDate: (UserDefaults.standard.object(forKey: .proEntitlementExpiration) as? Double).map(Date.init(timeIntervalSince1970:)),
            now: .now
        )
    }

    /// entitlement 判定を UserDefaults キャッシュへ保存する。
    /// customerInfoStream の監視・購入・復元の全経路で同じ形のキャッシュになるようここへ集約する
    static func cacheEntitlement(customerInfo: CustomerInfo) {
        let entitlement = customerInfo.entitlements[entitlementIdentifier]
        UserDefaults.standard.set(entitlement?.isActive == true, forKey: .proEntitlementActive)
        let expirationDate = effectiveExpirationDate(
            expirationDate: entitlement?.expirationDate,
            gracePeriodExpiresDate: entitlement.flatMap { customerInfo.subscriptionsByProductIdentifier[$0.productIdentifier]?.gracePeriodExpiresDate }
        )
        if let expirationDate {
            UserDefaults.standard.set(expirationDate.timeIntervalSince1970, forKey: .proEntitlementExpiration)
        } else {
            UserDefaults.standard.removeObject(forKey: .proEntitlementExpiration)
        }
    }

    /// RevenueCat SDK を初期化する。
    /// API key 未設定では何もしない。ユニットテスト・Preview ではネットワークに触れないよう configure しない。
    /// isConfigured を見て多重 configure を防ぐため冪等
    static func configureIfPossible() {
        guard !revenueCatAPIKey.isEmpty, !isUnitTest, !isPreview, !Purchases.isConfigured else { return }
        Purchases.configure(withAPIKey: revenueCatAPIKey)
    }

    /// Firebase Auth の uid を RevenueCat の App User ID に結び付ける。
    /// バックエンドは RevenueCat の webhook が運ぶ app_user_id を uid として users/{uid}.plan を更新する
    /// (functions/src/api/revenueCatWebhook.ts) ため、購入の前に uid でログインしておく必要がある。
    /// 匿名 ID で行った購入があれば RevenueCat 側で uid にマージされる。
    /// 未 configure (API key 無し・テスト・Preview) では何もせず、同じ uid で既にログイン済みなら通信しない (冪等)
    static func logIn(appUserID: String) async {
        guard Purchases.isConfigured, Purchases.shared.appUserID != appUserID else { return }
        do {
            let (customerInfo, _) = try await Purchases.shared.logIn(appUserID)
            cacheEntitlement(customerInfo: customerInfo)
        } catch {
            // 失敗しても次回の signIn (起動・前面復帰) で再試行する
            Logger.purchase.error("RevenueCat logIn failed: \(error.localizedDescription)")
        }
    }

    /// RevenueCat の App User ID がこの uid になっているか。未 configure では購入自体ができないため false
    static func isLoggedIn(as appUserID: String) -> Bool {
        Purchases.isConfigured && Purchases.shared.appUserID == appUserID
    }

    /// RevenueCat の identity を匿名 ID に戻す。既に匿名なら何もしない (冪等。匿名の logOut は SDK がエラーにする)
    static func logOut() async {
        guard Purchases.isConfigured, !Purchases.shared.isAnonymous else { return }
        do {
            let customerInfo = try await Purchases.shared.logOut()
            cacheEntitlement(customerInfo: customerInfo)
        } catch {
            Logger.purchase.error("RevenueCat logOut failed: \(error.localizedDescription)")
        }
    }

    /// customerInfoStream を監視して entitlement 判定のキャッシュを更新し続ける。
    /// 起動時キャッシュ → 購入・復元・期限切れ更新の順に customerInfo が流れてくるため、この 1 本で課金状態へ追従できる
    static func observeCustomerInfo() async {
        guard Purchases.isConfigured else { return }
        for await customerInfo in Purchases.shared.customerInfoStream {
            cacheEntitlement(customerInfo: customerInfo)
        }
    }
}
