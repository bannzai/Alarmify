import XCTest
@testable import Alarmify

/// API トークン画面の表示ロジック (curl の例・スタブ経由の一覧と失効) のテスト
final class APITokenTests: XCTestCase {
    func testCurlExampleIsASingleLineWithTheSecretAndFireAt() {
        let example = APITokenUsageExample.curl(
            secret: "alm_1a2b_secret",
            backend: .production,
            fireDate: Date(timeIntervalSince1970: 1_788_343_200),
            title: "Deploy finished"
        )

        XCTAssertEqual(
            example,
            "curl -X POST https://asia-northeast1-alarmify-prod.cloudfunctions.net/api/v1/alarms -H 'Authorization: Bearer alm_1a2b_secret' -H 'Content-Type: application/json' -d '{\"fire_at\":\"2026-09-02T10:00:00Z\",\"title\":\"Deploy finished\"}'"
        )
        XCTAssertFalse(example.contains("\n"))
    }

    func testCurlExamplePointsAtTheSelectedBackend() {
        let example = APITokenUsageExample.curl(
            secret: "secret",
            backend: .emulator,
            fireDate: Date(timeIntervalSince1970: 0)
        )

        XCTAssertTrue(example.contains("http://127.0.0.1:5501/demo-alarmify/asia-northeast1/api/v1/alarms"), example)
    }

    @MainActor
    func testIssueThenRevokeUpdatesTheList() async {
        // 保存済みの開発者設定を書き換えないよう、shared ではなくテスト専用のインスタンスを組み立てる
        let session = AccountSession(settings: DeveloperSettings(backend: .emulator, stubAPIClient: true))
        let model = APITokenModel(session: session)

        await model.issue()

        XCTAssertEqual(model.tokens.count, 1)
        XCTAssertNil(model.errorMessage)
        let issued = try? XCTUnwrap(model.issued)
        XCTAssertEqual(model.curlExample?.contains(issued?.secret ?? "-"), true)

        await model.revoke(id: issued?.token.id ?? "")

        XCTAssertTrue(model.tokens.isEmpty)
        // 失効させたトークンの平文は表示に残さない
        XCTAssertNil(model.issued)
    }
}
