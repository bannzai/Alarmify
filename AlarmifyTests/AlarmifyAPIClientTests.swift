import XCTest
@testable import Alarmify

/// URLProtocol で応答を差し替え、通信層がリクエストを組み立て・応答を型付き struct に変換できることを検証する
final class AlarmifyAPIClientTests: XCTestCase {
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

    func testAPITokensAreDecodedIntoTypedStructs() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path(), "/demo-alarmify/asia-northeast1/api/v1/me/apiTokens")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer id-token")
            let body = """
            {"apiTokens":[{"id":"tok_1","prefix":"alm_9f2c","createdAt":"2026-09-02T10:00:00Z","lastUsedAt":null}]}
            """
            return (200, Data(body.utf8))
        }

        let tokens = try await makeClient().apiTokens()

        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens.first?.id, "tok_1")
        XCTAssertEqual(tokens.first?.prefix, "alm_9f2c")
        XCTAssertEqual(tokens.first?.createdAt, Date(timeIntervalSince1970: 1_788_343_200))
        XCTAssertNil(tokens.first?.lastUsedAt)
    }

    func testIssuedTokenCarriesTheSecretOnlyReturnedOnce() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            let body = """
            {"apiToken":{"id":"tok_2","prefix":"alm_1a2b","createdAt":"2026-09-02T10:00:00Z","lastUsedAt":null},"secret":"alm_1a2b_secret"}
            """
            return (200, Data(body.utf8))
        }

        let issued = try await makeClient().issueAPIToken()

        XCTAssertEqual(issued.token.id, "tok_2")
        XCTAssertEqual(issued.secret, "alm_1a2b_secret")
    }

    func testRegisterDeviceSendsFCMRegistrationToken() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path(), "/demo-alarmify/asia-northeast1/api/v1/me/devices")
            let body = (try? JSONSerialization.jsonObject(with: StubURLProtocol.body(of: request))) as? [String: String]
            XCTAssertEqual(body?["fcm_registration_token"], "fcm-token")
            return (204, Data())
        }

        try await makeClient().registerDevice(fcmRegistrationToken: "fcm-token")
    }

    func testRevokeUsesTheTokenIdInThePath() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path(), "/demo-alarmify/asia-northeast1/api/v1/me/apiTokens/tok_3")
            return (204, Data())
        }

        try await makeClient().revokeAPIToken(id: "tok_3")
    }

    func testServerErrorMessageIsSurfacedAsIs() async {
        StubURLProtocol.handler = { _ in
            (429, Data(#"{"error":{"message":"Free plan allows 20 alarms per month"}}"#.utf8))
        }

        do {
            _ = try await makeClient().apiTokens()
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(
                error as? AlarmifyAPIError,
                .server(statusCode: 429, message: "Free plan allows 20 alarms per month")
            )
        }
    }

    func testNonJSONErrorBodyIsSurfacedAsIs() async {
        StubURLProtocol.handler = { _ in (500, Data("Internal Server Error".utf8)) }

        do {
            _ = try await makeClient().apiTokens()
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? AlarmifyAPIError, .server(statusCode: 500, message: "Internal Server Error"))
        }
    }

    func testRequestIsNotSentWhileSignedOut() async {
        StubURLProtocol.handler = { _ in
            XCTFail("The request must not be sent while signed out")
            return (200, Data())
        }

        do {
            _ = try await makeClient(idToken: nil).apiTokens()
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? AlarmifyAPIError, .notSignedIn)
        }
    }

    func testMalformedSuccessBodyIsRejectedInsteadOfDefaulted() async {
        StubURLProtocol.handler = { _ in (200, Data(#"{"apiTokens":[{"id":"tok_4"}]}"#.utf8)) }

        do {
            _ = try await makeClient().apiTokens()
            XCTFail("Expected an error")
        } catch {
            guard case .invalidResponse = error as? AlarmifyAPIError else {
                return XCTFail("Expected invalidResponse but got \(error)")
            }
        }
    }
}

/// テスト中の HTTP 応答を差し替える URLProtocol
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?

    /// URLProtocol に渡る URLRequest は httpBody が剥がされて httpBodyStream になるため、ストリームから読み直す
    static func body(of request: URLRequest) -> Data {
        if let httpBody = request.httpBody { return httpBody }
        guard let stream = request.httpBodyStream else { return Data() }
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

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let (statusCode, data) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
