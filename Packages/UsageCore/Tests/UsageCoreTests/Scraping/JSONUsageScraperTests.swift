import XCTest
@testable import UsageCore

final class JSONUsageScraperTests: XCTestCase {
    func test_fetchSnapshot_parses_known_shape() async throws {
        // Real shape observed from claude.ai/api/organizations/{id}/usage
        // on 2026-04-30. utilization is a percentage (0-100), reset times
        // are ISO 8601 with microsecond precision.
        let body = """
        {
            "five_hour": {
                "utilization": 3.0,
                "resets_at": "2026-04-30T19:09:59.955046+00:00"
            },
            "seven_day": {
                "utilization": 59.0,
                "resets_at": "2026-04-30T20:59:59.955071+00:00"
            },
            "seven_day_oauth_apps": null,
            "seven_day_opus": null,
            "seven_day_sonnet": {
                "utilization": 6.0,
                "resets_at": "2026-04-30T20:59:59.955082+00:00"
            },
            "seven_day_cowork": null,
            "seven_day_omelette": {
                "utilization": 0.0,
                "resets_at": null
            },
            "tangelo": null,
            "iguana_necktie": null,
            "omelette_promotional": null,
            "extra_usage": {
                "is_enabled": false,
                "monthly_limit": null,
                "used_credits": null,
                "utilization": null,
                "currency": null
            }
        }
        """.data(using: .utf8)!
        URLProtocolMock.responses[URL(string: "https://claude.ai/api/usage")!] = (200, body)
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [URLProtocolMock.self]
        let session = URLSession(configuration: cfg)

        let scraper = JSONUsageScraper(
            endpoint: URL(string: "https://claude.ai/api/usage")!,
            cookies: CookiePackage(sessionKey: "s", cfClearance: nil, cfBm: nil, userAgent: "UA", all: []),
            session: session
        )
        let snap = try await scraper.fetchSnapshot()
        // 3.0% × 100 = 300 ; ceiling = 10000
        XCTAssertEqual(snap.used5h, 300)
        XCTAssertEqual(snap.ceiling5h, 10_000)
        XCTAssertEqual(snap.fraction5h, 0.03, accuracy: 0.0001)
        XCTAssertEqual(snap.usedWeek, 5900)
        XCTAssertEqual(snap.ceilingWeek, 10_000)
        XCTAssertEqual(snap.fractionWeek, 0.59, accuracy: 0.0001)
    }

    func test_fetchSnapshot_handles_missing_windows() async throws {
        // If the user has zero usage, Anthropic might return null.
        let body = """
        {"five_hour": null, "seven_day": null}
        """.data(using: .utf8)!
        URLProtocolMock.responses[URL(string: "https://claude.ai/api/usage")!] = (200, body)
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [URLProtocolMock.self]
        let session = URLSession(configuration: cfg)
        let scraper = JSONUsageScraper(
            endpoint: URL(string: "https://claude.ai/api/usage")!,
            cookies: CookiePackage(sessionKey: "s", cfClearance: nil, cfBm: nil, userAgent: "UA", all: []),
            session: session)
        let snap = try await scraper.fetchSnapshot()
        XCTAssertEqual(snap.used5h, 0)
        XCTAssertEqual(snap.usedWeek, 0)
    }

    func test_401_throws_authExpired() async throws {
        URLProtocolMock.responses[URL(string: "https://claude.ai/api/usage")!] = (401, Data())
        let cfg = URLSessionConfiguration.ephemeral; cfg.protocolClasses = [URLProtocolMock.self]
        let session = URLSession(configuration: cfg)
        let scraper = JSONUsageScraper(
            endpoint: URL(string: "https://claude.ai/api/usage")!,
            cookies: CookiePackage(sessionKey: "", cfClearance: nil, cfBm: nil, userAgent: "UA", all: []),
            session: session)
        do { _ = try await scraper.fetchSnapshot(); XCTFail() }
        catch let e as ScrapeError { XCTAssertEqual(e, .authExpired) }
    }
}

final class URLProtocolMock: URLProtocol {
    static var responses: [URL: (Int, Data)] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for r: URLRequest) -> URLRequest { r }
    override func startLoading() {
        guard let url = request.url, let (status, body) = Self.responses[url] else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        let resp = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
