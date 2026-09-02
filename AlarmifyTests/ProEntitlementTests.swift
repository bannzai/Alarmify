import XCTest

@testable import Alarmify

/// entitlement キャッシュの有効判定 (cachedProActive) のテスト。
/// 購読はアプリ停止中に失効し得るため、保存した active をそのまま信じると失効後も Pro のまま見えてしまう。
/// 一方で失効日時を過ぎていても RevenueCat が有効と判定した (請求猶予期間など) 場合はその判定を尊重する
final class ProEntitlementTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// 未購入は失効日時・判定時刻の有無によらず false
    func testInactiveIsNotPro() {
        XCTAssertFalse(cachedProActive(active: false, expirationDate: nil, evaluatedAt: nil, now: now))
        XCTAssertFalse(cachedProActive(active: false, expirationDate: now.addingTimeInterval(60), evaluatedAt: now, now: now))
    }

    /// 失効日時が未来なら有効
    func testActiveBeforeExpirationIsPro() {
        XCTAssertTrue(cachedProActive(active: true, expirationDate: now.addingTimeInterval(60), evaluatedAt: nil, now: now))
    }

    /// 失効日時を過ぎ、RevenueCat の判定が失効日時より前なら、保存された active が true でも無効
    func testActiveAfterExpirationEvaluatedBeforeExpirationIsNotPro() {
        let expiration = now.addingTimeInterval(-60)
        XCTAssertFalse(cachedProActive(active: true, expirationDate: expiration, evaluatedAt: expiration.addingTimeInterval(-3600), now: now))
        XCTAssertFalse(cachedProActive(active: true, expirationDate: expiration, evaluatedAt: nil, now: now))
    }

    /// 失効日時を過ぎていても、RevenueCat が失効日時以降に有効と判定していれば (請求猶予期間) 有効のまま
    func testActiveAfterExpirationEvaluatedAfterExpirationIsPro() {
        let expiration = now.addingTimeInterval(-60)
        XCTAssertTrue(cachedProActive(active: true, expirationDate: expiration, evaluatedAt: expiration, now: now))
        XCTAssertTrue(cachedProActive(active: true, expirationDate: expiration, evaluatedAt: now.addingTimeInterval(-30), now: now))
    }

    /// 失効日時ちょうどは失効済みとして扱う (判定時刻がそれより前の場合)
    func testActiveAtExpirationIsNotPro() {
        XCTAssertFalse(cachedProActive(active: true, expirationDate: now, evaluatedAt: now.addingTimeInterval(-1), now: now))
    }

    /// 失効日時が無い (買い切り) 場合は active をそのまま使う
    func testActiveWithoutExpirationIsPro() {
        XCTAssertTrue(cachedProActive(active: true, expirationDate: nil, evaluatedAt: nil, now: now))
    }
}
