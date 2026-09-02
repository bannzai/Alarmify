import XCTest
@testable import Alarmify

/// アカウント削除の HTTP 呼び出しと、削除後にローカルの状態が初期化されることのテスト
final class AccountDeletionTests: XCTestCase {
    private let endpoint = URL(string: "https://example.com/deleteAccount")!
    private let credential = AccountCredential(userId: "uid-1234", idToken: "id-token-1234")

    private var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override func tearDown() {
        StubURLProtocol.response = nil
        StubURLProtocol.requests = []
        AccountStore.clear()
        DeviceTokenStore.clear()
        super.tearDown()
    }

    func testDeleteAccountSendsCallableRequestWithIDToken() async throws {
        StubURLProtocol.response = .init(statusCode: 200, body: Data(#"{"result":{"userId":"uid-1234"}}"#.utf8))

        try await RemoteAccountDeletionService(endpoint: endpoint, session: session).deleteAccount(credential: credential)

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
        XCTAssertEqual(request.url, endpoint)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer id-token-1234")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        // 削除対象は ID トークンの uid でサーバーが決めるため、パラメータを送らない
        let body = try JSONSerialization.jsonObject(with: try XCTUnwrap(request.body)) as? [String: Any]
        XCTAssertEqual(body?.count, 1)
        XCTAssertEqual((body?["data"] as? [String: Any])?.isEmpty, true)
    }

    func testDeleteAccountThrowsServerMessageOnError() async {
        StubURLProtocol.response = .init(
            statusCode: 401,
            body: Data(#"{"error":{"message":"Authentication is required to delete the account.","status":"UNAUTHENTICATED"}}"#.utf8)
        )

        do {
            try await RemoteAccountDeletionService(endpoint: endpoint, session: session).deleteAccount(credential: credential)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(
                error as? AccountDeletionError,
                .server(message: "Authentication is required to delete the account.")
            )
        }
    }

    func testDeleteAccountThrowsStatusCodeWhenBodyIsNotCallableError() async {
        StubURLProtocol.response = .init(statusCode: 500, body: Data("internal error".utf8))

        do {
            try await RemoteAccountDeletionService(endpoint: endpoint, session: session).deleteAccount(credential: credential)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? AccountDeletionError, .server(message: "HTTP 500"))
        }
    }

    func testAccountStoreClearRemovesCredentialAndIsIdempotent() {
        AccountStore.save(credential)
        XCTAssertEqual(AccountStore.load(), credential)

        AccountStore.clear()
        AccountStore.clear()

        XCTAssertNil(AccountStore.load())
    }

    func testDeviceTokenStoreClearRemovesToken() {
        DeviceTokenStore.save("0123456789abcdef")

        DeviceTokenStore.clear()

        XCTAssertNil(DeviceTokenStore.load())
    }
}

/// URLSession のリクエストを横取りして固定のレスポンスを返すスタブ
private final class StubURLProtocol: URLProtocol {
    struct Response {
        let statusCode: Int
        let body: Data
    }

    /// テストが用意するレスポンスと、記録したリクエスト。テストは直列に実行されるため static で共有する
    nonisolated(unsafe) static var response: Response?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        guard let stub = Self.response else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: stub.statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension URLRequest {
    /// URLProtocol へ渡るリクエストは httpBody が nil になり、httpBodyStream にだけ本文が入る
    var body: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
