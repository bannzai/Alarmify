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

    private func makeClient(idToken: String? = "id-token", appCheckToken: String? = nil) -> URLSessionAlarmifyAPIClient {
        URLSessionAlarmifyAPIClient(
            backend: .emulator,
            session: session,
            deviceID: "device-1",
            idToken: { idToken },
            appCheckToken: { appCheckToken }
        )
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
            (429, Data(#"{"error":{"code":"rate_limited","message":"Free plan allows 20 alarms per month"}}"#.utf8))
        }

        do {
            _ = try await makeClient().apiTokens()
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(
                error as? AlarmifyAPIError,
                .server(statusCode: 429, code: "rate_limited", message: "Free plan allows 20 alarms per month")
            )
            XCTAssertEqual((error as? AlarmifyAPIError)?.isPlanLimitExceeded, false)
        }
    }

    /// 無料プランの上限で発行を拒否された応答は、ペイウォールへ誘導する判定 (`plan_limit_exceeded`) として受け取る
    func testPlanLimitExceededIsRecognizedFromTheErrorCode() async {
        StubURLProtocol.handler = { _ in
            (403, Data(#"{"error":{"code":"plan_limit_exceeded","message":"free プランで発行できる API トークンは 1 個までです"}}"#.utf8))
        }

        do {
            _ = try await makeClient().issueAPIToken()
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(
                error as? AlarmifyAPIError,
                .server(statusCode: 403, code: "plan_limit_exceeded", message: "free プランで発行できる API トークンは 1 個までです")
            )
            XCTAssertEqual((error as? AlarmifyAPIError)?.isPlanLimitExceeded, true)
        }
    }

    func testNonJSONErrorBodyIsSurfacedAsIs() async {
        StubURLProtocol.handler = { _ in (500, Data("Internal Server Error".utf8)) }

        do {
            _ = try await makeClient().apiTokens()
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? AlarmifyAPIError, .server(statusCode: 500, code: nil, message: "Internal Server Error"))
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

    /// App Check のトークンが取れたら、サーバーが検証できるようヘッダーに載せる
    func testAppCheckTokenIsSentInTheHeader() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Firebase-AppCheck"), "app-check-token")
            return (200, Data(#"{"api_tokens":[],"next_cursor":null}"#.utf8))
        }

        _ = try await makeClient(appCheckToken: "app-check-token").apiTokens()
    }

    /// App Attest 非対応の端末やトークン取得の失敗でも、リクエスト自体は送る
    /// (サーバーが監視のみのモードで運用している間に、正当な利用まで落とさないため)
    func testRequestIsStillSentWithoutTheAppCheckHeader() async throws {
        nonisolated(unsafe) var requestCount = 0
        StubURLProtocol.handler = { request in
            requestCount += 1
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Firebase-AppCheck"))
            return (200, Data(#"{"api_tokens":[],"next_cursor":null}"#.utf8))
        }

        _ = try await makeClient(appCheckToken: nil).apiTokens()

        XCTAssertEqual(requestCount, 1)
    }

    /// Callable の `deleteAccount` も同じ送信経路を通るため、ヘッダーが付く
    func testDeleteAccountCarriesTheAppCheckHeader() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:5410/demo-alarmify/asia-northeast1/deleteAccount")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Firebase-AppCheck"), "app-check-token")
            return (200, Data(#"{"result":{"userId":"uid-1234","authUserExisted":true,"userDocumentExisted":true}}"#.utf8))
        }

        try await makeClient(appCheckToken: "app-check-token").deleteAccount()
    }

    /// 履歴は配送結果と端末側の反映結果つきで届く。古いバックエンドの応答 (`delivery` / `device_reports` 無し) も受け付ける
    func testAlarmHistoryIsDecodedWithDeliveryAndDeviceReports() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            XCTAssertEqual(components?.path, "/demo-alarmify/asia-northeast1/appApi/v1/alarms")
            XCTAssertEqual(components?.queryItems?.first { $0.name == "limit" }?.value, "20")
            let body = """
            {"alarms":[
              {"id":"3b0e0c6e-9f1b-4c0a-9e7d-1f2a3b4c5d6e","status":"scheduled","title":"Deploy finished","fire_at":"2026-09-03T07:00:00.000Z","created_at":"2026-09-02T10:00:00.000Z","updated_at":"2026-09-02T10:00:00.000Z","token_id":"tok_1","delivery":{"success_count":1,"failure_count":0},"device_reports":[{"device_id":"device-1","action":"schedule","result":"failed","error":"maximumLimitReached","occurred_at":"2026-09-02T10:00:05Z"}]},
              {"id":"7f6d8c1a-2b3e-4f50-9a61-0b1c2d3e4f5a","status":"canceled","title":null,"fire_at":"2026-09-03T08:00:00.000Z","created_at":"2026-09-02T11:00:00.000Z","token_id":"tok_1"}
            ],"next_cursor":null}
            """
            return (200, Data(body.utf8))
        }

        let history = try await makeClient().alarmHistory(limit: 20)

        XCTAssertEqual(history.map(\.id), ["3b0e0c6e-9f1b-4c0a-9e7d-1f2a3b4c5d6e", "7f6d8c1a-2b3e-4f50-9a61-0b1c2d3e4f5a"])
        XCTAssertEqual(history[0].status, .scheduled)
        XCTAssertEqual(history[0].title, "Deploy finished")
        XCTAssertEqual(history[0].fireAt, Date(timeIntervalSince1970: 1_788_418_800))
        XCTAssertEqual(history[0].delivery, AlarmHistoryEntry.Delivery(successCount: 1, failureCount: 0))
        XCTAssertEqual(
            history[0].deviceReport(deviceID: "device-1"),
            AlarmHistoryEntry.DeviceReport(deviceID: "device-1", action: .schedule, result: .failed, error: "maximumLimitReached", occurredAt: Date(timeIntervalSince1970: 1_788_343_205))
        )
        XCTAssertNil(history[0].deviceReport(deviceID: "device-2"))
        XCTAssertEqual(history[1].status, .canceled)
        XCTAssertNil(history[1].title)
        XCTAssertNil(history[1].delivery)
        XCTAssertEqual(history[1].deviceReports, [])
    }

    /// 端末側の反映結果は、この端末の device_id と秒精度の occurred_at を付けてアラーム id のパスへ送る
    func testReportAlarmApplySendsTheDeviceIdAndResult() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path(), "/demo-alarmify/asia-northeast1/appApi/v1/alarms/3b0e0c6e-9f1b-4c0a-9e7d-1f2a3b4c5d6e/device-reports")
            let body = (try? JSONSerialization.jsonObject(with: StubURLProtocol.body(of: request))) as? [String: String]
            XCTAssertEqual(body, [
                "device_id": "device-1",
                "action": "schedule",
                "result": "failed",
                "error": "maximumLimitReached",
                "occurred_at": "2026-09-03T07:00:00Z",
            ])
            return (200, Data(#"{"alarm_id":"3b0e0c6e-9f1b-4c0a-9e7d-1f2a3b4c5d6e","device_id":"device-1"}"#.utf8))
        }

        try await makeClient().reportAlarmApply(AlarmApplyReport(
            alarmID: UUID(uuidString: "3B0E0C6E-9F1B-4C0A-9E7D-1F2A3B4C5D6E")!,
            action: .schedule,
            result: .failed,
            error: "maximumLimitReached",
            occurredAt: Date(timeIntervalSince1970: 1_788_418_800)
        ))
    }

    /// 成功した報告は error を送らない (サーバー側で null になる)
    func testReportAlarmApplyOmitsTheErrorWhenApplied() async throws {
        StubURLProtocol.handler = { request in
            let body = (try? JSONSerialization.jsonObject(with: StubURLProtocol.body(of: request))) as? [String: String]
            XCTAssertEqual(Set(body?.keys.map { $0 } ?? []), ["device_id", "action", "result", "occurred_at"])
            XCTAssertEqual(body?["result"], "applied")
            return (200, Data(#"{"alarm_id":"3b0e0c6e-9f1b-4c0a-9e7d-1f2a3b4c5d6e","device_id":"device-1"}"#.utf8))
        }

        try await makeClient().reportAlarmApply(AlarmApplyReport(
            alarmID: UUID(uuidString: "3B0E0C6E-9F1B-4C0A-9E7D-1F2A3B4C5D6E")!,
            action: .cancel,
            result: .applied,
            error: nil,
            occurredAt: Date(timeIntervalSince1970: 1_788_418_800)
        ))
    }

    /// 404 は「報告先のアラームがサーバーに無い」判定 (`isNotFound`) として受け取り、報告を捨てる側の分岐に使う
    func testNotFoundIsRecognizedFromTheStatusCode() async {
        StubURLProtocol.handler = { _ in
            (404, Data(#"{"error":{"code":"not_found","message":"アラームが見つかりません"}}"#.utf8))
        }

        do {
            try await makeClient().reportAlarmApply(AlarmApplyReport(alarmID: UUID(), action: .schedule, result: .applied, error: nil, occurredAt: .now))
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual((error as? AlarmifyAPIError)?.isNotFound, true)
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
