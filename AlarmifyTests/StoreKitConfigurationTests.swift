import StoreKit
import StoreKitTest
import XCTest

@testable import Alarmify

/// StoreKit Configuration file (Alarmify.storekit) の検証。
/// SKTestSession がテストバンドル内の .storekit を読み込むため、App Store Connect・ネットワークに触れず
/// CLI (xcodebuild test) だけで「商品解決 → 購入 → entitlement 付与」まで確認できる
final class StoreKitConfigurationTests: XCTestCase {
    /// 商品識別子は ~/.claude/documents/rules/iap-product-identifier-naming.md の
    /// `<プロダクト名>_<プラン名>_<期間>_<価格>` に従う。App Store Connect へ登録した後は変更できない
    private let annualProductID = "alarmify_pro_annual_2300yen"
    private let monthlyProductID = "alarmify_pro_monthly_450yen"

    /// iOS 26.5 の simulator では xcodebuild test 経由の StoreKit Testing が機能しない既知の問題があるため skip する。
    /// SKTestSession の init は成功するのに設定が適用されず、商品解決が実ストア (sandbox) に落ちる
    /// (bannzai/mementomorning の同名テストで実測済み。iOS 26.2 以下の runtime では全項目 pass)
    private func skipOnBrokenSimulatorRuntime() throws {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        try XCTSkipIf(
            version.majorVersion == 26 && version.minorVersion == 5,
            "iOS 26.5 simulator では StoreKit Testing が機能しない (iOS 26.2 以下の runtime で実行する)"
        )
    }

    /// 2 つの購読商品が識別子どおりの価格・購読期間で解決されること
    func testProductsResolveWithConfiguredPrices() async throws {
        try skipOnBrokenSimulatorRuntime()
        let session = try SKTestSession(configurationFileNamed: "Alarmify")
        session.resetToDefaultState()
        session.clearTransactions()

        let products = try await Product.products(for: [annualProductID, monthlyProductID])
        let productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })

        XCTAssertEqual(productsByID.count, 2)
        XCTAssertEqual(productsByID[annualProductID]?.price, 2300)
        XCTAssertEqual(productsByID[monthlyProductID]?.price, 450)

        XCTAssertEqual(productsByID[annualProductID]?.subscription?.subscriptionPeriod.unit, .year)
        XCTAssertEqual(productsByID[monthlyProductID]?.subscription?.subscriptionPeriod.unit, .month)

        // 無料トライアルは documents/PROJECT.md の課金設計に無いため、どちらの商品にも設定しない
        XCTAssertNil(productsByID[annualProductID]?.subscription?.introductoryOffer)
        XCTAssertNil(productsByID[monthlyProductID]?.subscription?.introductoryOffer)
    }

    /// 年額プランを 1 つの購読グループにまとめ、月額から年額への切り替えが同一グループ内で行えること
    func testPlansShareSubscriptionGroup() async throws {
        try skipOnBrokenSimulatorRuntime()
        let session = try SKTestSession(configurationFileNamed: "Alarmify")
        session.resetToDefaultState()
        session.clearTransactions()

        let products = try await Product.products(for: [annualProductID, monthlyProductID])
        let groupIDs = Set(products.compactMap { $0.subscription?.subscriptionGroupID })

        XCTAssertEqual(groupIDs.count, 1)
    }

    /// テスト購入でトランザクションが成立し、現在の entitlement に現れること
    func testBuyAnnualGrantsEntitlement() async throws {
        try skipOnBrokenSimulatorRuntime()
        let session = try SKTestSession(configurationFileNamed: "Alarmify")
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true

        _ = try await session.buyProduct(identifier: annualProductID)

        var entitledProductIDs: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                entitledProductIDs.insert(transaction.productID)
            }
        }
        XCTAssertTrue(entitledProductIDs.contains(annualProductID))
    }
}
