import XCTest
@testable import Alarmify

/// アカウント削除の Callable 呼び出し (リクエストの組み立てとエラーの扱い) と、スタブでの削除のテスト
final class AccountDeletionTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: configuration)
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        session = nil
        super.tearDown()
    }

    private func makeClient(idToken: String? = "id-token") -> URLSessionAlarmifyAPIClient {
        URLSessionAlarmifyAPIClient(backend: .emulator, session: session) { idToken }
    }

    func testDeleteAccountCallsTheCallableWithTheIDToken() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            // `api` ではなく Callable 関数 `deleteAccount` を直接呼ぶ
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:5410/demo-alarmify/asia-northeast1/deleteAccount")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer id-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            // 削除対象は ID トークンの uid でサーバーが決めるため、パラメータを送らない
            let body = (try? JSONSerialization.jsonObject(with: StubURLProtocol.body(of: request))) as? [String: Any]
            XCTAssertEqual(body?.count, 1)
            XCTAssertEqual((body?["data"] as? [String: Any])?.isEmpty, true)
            return (200, Data(#"{"result":{"userId":"uid-1234","authUserExisted":true,"userDocumentExisted":true}}"#.utf8))
        }

        try await makeClient().deleteAccount()
    }

    func testDeleteAccountSurfacesTheCallableErrorMessage() async {
        StubURLProtocol.handler = { _ in
            (401, Data(#"{"error":{"message":"Authentication is required to delete the account.","status":"UNAUTHENTICATED"}}"#.utf8))
        }

        do {
            try await makeClient().deleteAccount()
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(
                error as? AlarmifyAPIError,
                .server(statusCode: 401, message: "Authentication is required to delete the account.")
            )
        }
    }

    /// 200 でも Callable の `result` が無い応答は成功扱いにしない (削除していないのにアカウントを画面から消さない)
    func testDeleteAccountRejectsAResponseWithoutResult() async {
        StubURLProtocol.handler = { _ in (200, Data("<html>proxy</html>".utf8)) }

        do {
            try await makeClient().deleteAccount()
            XCTFail("Expected an error")
        } catch {
            guard case .invalidResponse? = error as? AlarmifyAPIError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testDeleteAccountRequiresSignIn() async {
        StubURLProtocol.handler = { _ in
            XCTFail("The request must not be sent without an ID token")
            return (200, Data())
        }

        do {
            try await makeClient(idToken: nil).deleteAccount()
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? AlarmifyAPIError, .notSignedIn)
        }
    }

    func testStubDeleteAccountRemovesIssuedTokens() async throws {
        let client = StubAlarmifyAPIClient()
        _ = try await client.issueAPIToken()

        try await client.deleteAccount()

        let tokens = try await client.apiTokens()
        XCTAssertTrue(tokens.isEmpty)
    }
}
