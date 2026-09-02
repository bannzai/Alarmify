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
        URLSessionAlarmifyAPIClient(backend: .emulator, session: session, deviceID: "device-1") { idToken }
    }

    func testAPITokensAreDecodedIntoTypedStructs() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path(), "/demo-alarmify/asia-northeast1/appApi/v1/api-tokens")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer id-token")
            // 日時はバックエンドの Date.toISOString() と同じ小数秒つきの形で返る
            let body = """
            {"api_tokens":[{"id":"tok_1","name":"ci","prefix":"alm_9f2c","created_at":"2026-09-02T10:00:00.000Z","last_used_at":null}],"next_cursor":null}
            """
            return (200, Data(body.utf8))
        }

        let tokens = try await makeClient().apiTokens()

        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens.first?.id, "tok_1")
        XCTAssertEqual(tokens.first?.name, "ci")
        XCTAssertEqual(tokens.first?.prefix, "alm_9f2c")
        XCTAssertEqual(tokens.first?.createdAt, Date(timeIntervalSince1970: 1_788_343_200))
        XCTAssertNil(tokens.first?.lastUsedAt)
    }

    func testIssuedTokenCarriesTheSecretOnlyReturnedOnce() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path(), "/demo-alarmify/asia-northeast1/appApi/v1/api-tokens")
            // 発行の応答は入れ子が無く、`token` が平文の値。小数秒の無い日時も受け付ける
            let body = """
            {"id":"tok_2","name":"default","prefix":"alm_1a2b","token":"alm_1a2b_secret","created_at":"2026-09-02T10:00:00Z"}
            """
            return (201, Data(body.utf8))
        }

        let issued = try await makeClient().issueAPIToken()

        XCTAssertEqual(issued.token.id, "tok_2")
        XCTAssertEqual(issued.token.name, "default")
        XCTAssertEqual(issued.token.prefix, "alm_1a2b")
        XCTAssertEqual(issued.token.createdAt, Date(timeIntervalSince1970: 1_788_343_200))
        XCTAssertNil(issued.token.lastUsedAt)
        XCTAssertEqual(issued.secret, "alm_1a2b_secret")
    }

    /// 1 ページに収まらない一覧でも、失効させたいトークンが隠れないよう最後まで辿る
    func testAPITokensFollowsThePaginationCursor() async throws {
        nonisolated(unsafe) var requestedCursors: [String?] = []
        StubURLProtocol.handler = { request in
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            let cursor = components?.queryItems?.first { $0.name == "cursor" }?.value
            requestedCursors.append(cursor)
            XCTAssertEqual(components?.queryItems?.first { $0.name == "limit" }?.value, "100")
            if cursor == nil {
                let body = """
                {"api_tokens":[{"id":"tok_1","name":"ci","prefix":"alm_1","created_at":"2026-09-02T10:00:00.000Z","last_used_at":null}],"next_cursor":"cursor_1"}
                """
                return (200, Data(body.utf8))
            }
            let body = """
            {"api_tokens":[{"id":"tok_2","name":"cron","prefix":"alm_2","created_at":"2026-09-02T10:00:00.000Z","last_used_at":null}],"next_cursor":null}
            """
            return (200, Data(body.utf8))
        }

        let tokens = try await makeClient().apiTokens()

        XCTAssertEqual(tokens.map(\.id), ["tok_1", "tok_2"])
        XCTAssertEqual(requestedCursors, [nil, "cursor_1"])
    }

    /// 再インストールを跨いでも同じ端末として登録し直せるよう、同じ値を返し続ける
    func testDeviceIdentifierIsStableAcrossReads() {
        let first = DeviceIdentifier.current

        XCTAssertFalse(first.isEmpty)
        XCTAssertFalse(first.contains("/"), "device_id は Firestore のドキュメント id に使うため / を含められない")
        XCTAssertEqual(DeviceIdentifier.current, first)
    }

    func testRegisterDeviceSendsTheDeviceIdAndFCMToken() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path(), "/demo-alarmify/asia-northeast1/appApi/v1/devices")
            let body = (try? JSONSerialization.jsonObject(with: StubURLProtocol.body(of: request))) as? [String: String]
            XCTAssertEqual(body?["device_id"], "device-1")
            XCTAssertEqual(body?["fcm_token"], "fcm-token")
            XCTAssertEqual(body?["platform"], "ios")
            return (200, Data(#"{"device_id":"device-1","platform":"ios"}"#.utf8))
        }

        try await makeClient().registerDevice(fcmRegistrationToken: "fcm-token")
    }

    func testRevokeUsesTheTokenIdInThePath() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path(), "/demo-alarmify/asia-northeast1/appApi/v1/api-tokens/tok_3")
            return (204, Data())
        }

        try await makeClient().revokeAPIToken(id: "tok_3")
    }

    func testRevokeEscapesTheTokenIdExactlyOnce() async throws {
        StubURLProtocol.handler = { request in
            // 空白と `/` を含む id でも、1 度だけエスケープされた 1 セグメントとして届く
            XCTAssertEqual(
                request.url?.absoluteString,
                "http://127.0.0.1:5410/demo-alarmify/asia-northeast1/appApi/v1/api-tokens/tok%20a%2Fb"
            )
            return (204, Data())
        }

        try await makeClient().revokeAPIToken(id: "tok a/b")
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
        StubURLProtocol.handler = { _ in (200, Data(#"{"api_tokens":[{"id":"tok_4"}]}"#.utf8)) }

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
