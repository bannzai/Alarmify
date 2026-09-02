import XCTest

@testable import Alarmify

/// entitlement キャッシュの有効判定 (cachedProActive) と、キャッシュする失効日時の決定 (effectiveExpirationDate) のテスト。
/// 購読はアプリ停止中に失効し得るため、保存した active をそのまま信じると失効後も Pro のまま見えてしまう。
/// 一方で請求猶予期間中は expirationDate を過ぎてもアクセスが続くため、猶予期間の終了日時を失効日時として扱う
final class ProEntitlementTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// 未購入は失効日時の有無によらず false
    func testInactiveIsNotPro() {
        XCTAssertFalse(cachedProActive(active: false, expirationDate: nil, now: now))
        XCTAssertFalse(cachedProActive(active: false, expirationDate: now.addingTimeInterval(60), now: now))
    }

    /// 失効日時が未来なら有効
    func testActiveBeforeExpirationIsPro() {
        XCTAssertTrue(cachedProActive(active: true, expirationDate: now.addingTimeInterval(60), now: now))
    }

    /// 失効日時を過ぎていたら、保存された active が true でも無効
    func testActiveAfterExpirationIsNotPro() {
        XCTAssertFalse(cachedProActive(active: true, expirationDate: now.addingTimeInterval(-60), now: now))
    }

    /// 失効日時ちょうどは失効済みとして扱う
    func testActiveAtExpirationIsNotPro() {
        XCTAssertFalse(cachedProActive(active: true, expirationDate: now, now: now))
    }

    /// 失効日時が無い (買い切り) 場合は active をそのまま使う
    func testActiveWithoutExpirationIsPro() {
        XCTAssertTrue(cachedProActive(active: true, expirationDate: nil, now: now))
    }

    /// 猶予期間が無ければ entitlement の失効日時をそのまま使う
    func testEffectiveExpirationWithoutGracePeriod() {
        XCTAssertEqual(effectiveExpirationDate(expirationDate: now, gracePeriodExpiresDate: nil), now)
        XCTAssertNil(effectiveExpirationDate(expirationDate: nil, gracePeriodExpiresDate: nil))
    }

    /// 猶予期間の終了日時が失効日時より後なら、猶予期間の終了日時を失効日時として扱う (猶予期間中も Pro のまま)
    func testEffectiveExpirationUsesLaterGracePeriodEnd() {
        let graceEnd = now.addingTimeInterval(16 * 24 * 60 * 60)
        XCTAssertEqual(effectiveExpirationDate(expirationDate: now, gracePeriodExpiresDate: graceEnd), graceEnd)
        XCTAssertEqual(effectiveExpirationDate(expirationDate: nil, gracePeriodExpiresDate: graceEnd), graceEnd)
    }

    /// 猶予期間の終了日時が失効日時より前 (更新済みで古い猶予期間が残っている等) なら失効日時を使う
    func testEffectiveExpirationIgnoresEarlierGracePeriodEnd() {
        XCTAssertEqual(effectiveExpirationDate(expirationDate: now, gracePeriodExpiresDate: now.addingTimeInterval(-60)), now)
    }
}
