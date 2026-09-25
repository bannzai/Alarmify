import XCTest

@testable import Alarmify

/// Pro の購入を始める前の Sign in with Apple の確認 (purchaseSignInGate) のテスト。
/// 購入はアカウントに Apple の認証情報がリンクされている時だけ始め、サインインで統合した先が既に Pro なら二重に購入しない
final class PurchaseSignInGateTests: XCTestCase {
    /// 購入ボタンを押した時点でリンク済みなら、サインインを求めずに購入へ進む (Pro の判定はここでは見ない)
    func testLinkedAccountPurchasesWithoutSignIn() {
        XCTAssertEqual(purchaseSignInGate(signInOutcome: nil, isPro: false), .purchase)
        XCTAssertEqual(purchaseSignInGate(signInOutcome: nil, isPro: true), .purchase)
    }

    /// 未リンクでサインインを終え、Pro でなければそのまま購入へ進む
    func testSignedInAccountPurchases() {
        XCTAssertEqual(purchaseSignInGate(signInOutcome: .linked, isPro: false), .purchase)
    }

    /// 未リンクで Apple のシートを閉じたら購入しない
    func testCancelledSignInDoesNotPurchase() {
        XCTAssertEqual(purchaseSignInGate(signInOutcome: .cancelled, isPro: false), .cancelled)
        XCTAssertEqual(purchaseSignInGate(signInOutcome: .cancelled, isPro: true), .cancelled)
    }

    /// サインインに失敗したら購入せず、失敗の説明をそのまま表示する
    func testFailedSignInDoesNotPurchase() {
        XCTAssertEqual(purchaseSignInGate(signInOutcome: .failed("error"), isPro: false), .failed("error"))
    }

    /// サインインで統合した先が既に Pro なら、購入せずに Pro が有効であることを表示する
    func testSignedInIntoProAccountDoesNotPurchaseAgain() {
        XCTAssertEqual(purchaseSignInGate(signInOutcome: .linked, isPro: true), .alreadyPro)
    }
}
