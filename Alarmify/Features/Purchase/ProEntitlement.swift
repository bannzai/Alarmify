import Foundation
import RevenueCat

extension String {
    /// RevenueCat の entitlement 判定結果をキャッシュする UserDefaults キー。
    /// View 外 (push 受信後の処理など) から同期的に参照するため、customerInfoStream の更新をここへ保存する
    static let proEntitlementActive = "proEntitlementActive"
    /// entitlement の失効日時 (epoch 秒) をキャッシュする UserDefaults キー。
    /// 購読はアプリ停止中に失効し得るため、proEntitlementActive と対で保存して参照時に同期判定する
    static let proEntitlementExpiration = "proEntitlementExpiration"
    /// RevenueCat が entitlement を判定した時刻 (CustomerInfo.requestDate、epoch 秒) をキャッシュする UserDefaults キー。
    /// 失効日時を過ぎていても RevenueCat が有効と判定した (請求猶予期間など) 場合に、その判定を尊重するために保存する
    static let proEntitlementEvaluatedAt = "proEntitlementEvaluatedAt"
}

/// キャッシュした課金判定が now 時点でも有効か。
/// 失効日時が未来ならそのまま有効。失効日時を過ぎている場合は、RevenueCat がその失効日時より後に有効と判定していた
/// (Apple の請求猶予期間など、RevenueCat 側が正を持つ延長) 時だけ有効とし、それ以外は無効として
/// 期限切れ・返金がアプリ停止中に起きても古い true を返さないようにする (PR #20 レビュー指摘)。
/// 失効日時なしは買い切りまたは未購入で、active の値をそのまま使う。
/// 純粋関数であり、同じ入力に対して常に同じ出力を返す (冪等)
func cachedProActive(active: Bool, expirationDate: Date?, evaluatedAt: Date?, now: Date) -> Bool {
    guard active else { return false }
    guard let expirationDate else { return true }
    if expirationDate > now { return true }
    guard let evaluatedAt else { return false }
    return evaluatedAt >= expirationDate
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
            evaluatedAt: (UserDefaults.standard.object(forKey: .proEntitlementEvaluatedAt) as? Double).map(Date.init(timeIntervalSince1970:)),
            now: .now
        )
    }

    /// entitlement 判定を UserDefaults キャッシュへ保存する。
    /// customerInfoStream の監視・購入・復元の全経路で同じ形のキャッシュになるようここへ集約する
    static func cacheEntitlement(customerInfo: CustomerInfo) {
        let entitlement = customerInfo.entitlements[entitlementIdentifier]
        UserDefaults.standard.set(entitlement?.isActive == true, forKey: .proEntitlementActive)
        UserDefaults.standard.set(customerInfo.requestDate.timeIntervalSince1970, forKey: .proEntitlementEvaluatedAt)
        if let expirationDate = entitlement?.expirationDate {
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

    /// customerInfoStream を監視して entitlement 判定のキャッシュを更新し続ける。
    /// 起動時キャッシュ → 購入・復元・期限切れ更新の順に customerInfo が流れてくるため、この 1 本で課金状態へ追従できる
    static func observeCustomerInfo() async {
        guard Purchases.isConfigured else { return }
        for await customerInfo in Purchases.shared.customerInfoStream {
            cacheEntitlement(customerInfo: customerInfo)
        }
    }
}
