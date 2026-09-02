import XCTest

@testable import Alarmify

/// entitlement キャッシュの有効判定 (cachedProActive) のテスト。
/// 購読はアプリ停止中に失効し得るため、保存した active をそのまま信じると失効後も Pro のまま見えてしまう
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
}
