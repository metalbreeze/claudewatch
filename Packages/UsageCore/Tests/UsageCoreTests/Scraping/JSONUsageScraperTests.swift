import XCTest
@testable import UsageCore

final class JSONUsageScraperTests: XCTestCase {
    func test_fetchSnapshot_parses_known_shape() async throws {
        let body = """
        {"plan":"Pro",
         "fiveHourWindow":{"used":12345,"limit":100000,"resetAt":"2026-04-30T15:00:00Z"},
         "weeklyWindow":{"used":50000,"limit":1000000,"resetAt":"2026-05-04T00:00:00Z"}}
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
        XCTAssertEqual(snap.plan, .pro)
        XCTAssertEqual(snap.used5h, 12345)
        XCTAssertEqual(snap.ceilingWeek, 1_000_000)
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
