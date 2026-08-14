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

    // MARK: - limits[] / Fable parsing

    /// Builds a scraper wired to URLProtocolMock for the given JSON body.
    /// Each test uses a distinct URL so the shared `responses` dictionary
    /// can't leak state between tests.
    private func makeScraper(url: String, body: String) -> JSONUsageScraper {
        let u = URL(string: url)!
        URLProtocolMock.responses[u] = (200, body.data(using: .utf8)!)
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [URLProtocolMock.self]
        return JSONUsageScraper(
            endpoint: u,
            cookies: CookiePackage(sessionKey: "s", cfClearance: nil, cfBm: nil,
                                   userAgent: "UA", all: []),
            session: URLSession(configuration: cfg))
    }

    func test_limits_withFable_extractsUtilizationAndReset() async throws {
        // Real shape observed 2026-08-13. The Fable limit is the
        // weekly_scoped entry; is_active marks it as the binding one.
        let body = """
        {
            "five_hour": { "utilization": 26.0, "resets_at": "2026-08-13T15:09:59.783360+00:00" },
            "seven_day": { "utilization": 69.0, "resets_at": "2026-08-13T21:00:00.783384+00:00" },
            "limits": [
                { "kind": "session", "group": "session", "percent": 26,
                  "severity": "normal", "resets_at": "2026-08-13T15:09:59.783360+00:00",
                  "scope": null, "is_active": false },
                { "kind": "weekly_all", "group": "weekly", "percent": 69,
                  "severity": "normal", "resets_at": "2026-08-13T21:00:00.783384+00:00",
                  "scope": null, "is_active": false },
                { "kind": "weekly_scoped", "group": "weekly", "percent": 99,
                  "severity": "critical", "resets_at": "2026-08-13T20:59:59.783618+00:00",
                  "scope": { "model": { "id": null, "display_name": "Fable" }, "surface": null },
                  "is_active": true }
            ]
        }
        """
        let scraper = makeScraper(url: "https://claude.ai/api/fable-present", body: body)
        let snap = try await scraper.fetchSnapshot()
        XCTAssertEqual(snap.usedFable, 9900)          // 99 × 100
        XCTAssertEqual(snap.fractionFable ?? 0, 0.99, accuracy: 0.0001)
        XCTAssertTrue(snap.fableIsActive)
        // Assert the exact instant, not just non-nil: the Fable entry's
        // resets_at (2026-08-13T20:59:59.783618+00:00) is only one
        // second away from weekly_all's (2026-08-13T21:00:00.783384+00:00)
        // in this fixture, so a tight accuracy proves the value came
        // from the Fable entry specifically and not its neighbour.
        let gotResetFable = try XCTUnwrap(snap.resetTimeFable?.timeIntervalSince1970)
        // 2026-08-13T20:59:59.783618+00:00 as a Unix epoch, computed
        // independently of the scraper's own date parsing.
        let wantResetFable = 1_786_654_799.783618
        XCTAssertEqual(gotResetFable, wantResetFable, accuracy: 0.01)
        // Legacy top-level fields must still parse.
        XCTAssertEqual(snap.used5h, 2600)
        XCTAssertEqual(snap.usedWeek, 6900)
    }

    func test_limits_withoutFable_yieldsNilFable() async throws {
        let body = """
        {
            "five_hour": { "utilization": 26.0, "resets_at": "2026-08-13T15:09:59.783360+00:00" },
            "seven_day": { "utilization": 69.0, "resets_at": "2026-08-13T21:00:00.783384+00:00" },
            "limits": [
                { "kind": "session", "group": "session", "percent": 26,
                  "severity": "normal", "resets_at": "2026-08-13T15:09:59.783360+00:00",
                  "scope": null, "is_active": false },
                { "kind": "weekly_all", "group": "weekly", "percent": 69,
                  "severity": "normal", "resets_at": "2026-08-13T21:00:00.783384+00:00",
                  "scope": null, "is_active": false }
            ]
        }
        """
        let scraper = makeScraper(url: "https://claude.ai/api/fable-absent", body: body)
        let snap = try await scraper.fetchSnapshot()
        XCTAssertNil(snap.usedFable)
        XCTAssertNil(snap.fractionFable)
        XCTAssertNil(snap.resetTimeFable)
        XCTAssertFalse(snap.fableIsActive)
    }

    func test_limitsFieldAbsent_doesNotThrowSchemaDrift() async throws {
        // The pre-2026-08 response shape. Must still decode.
        let body = """
        {
            "five_hour": { "utilization": 3.0, "resets_at": "2026-04-30T19:09:59.955046+00:00" },
            "seven_day": { "utilization": 59.0, "resets_at": "2026-04-30T20:59:59.955071+00:00" },
            "seven_day_opus": null,
            "extra_usage": { "is_enabled": false }
        }
        """
        let scraper = makeScraper(url: "https://claude.ai/api/no-limits-key", body: body)
        let snap = try await scraper.fetchSnapshot()
        XCTAssertEqual(snap.used5h, 300)
        XCTAssertEqual(snap.usedWeek, 5900)
        XCTAssertNil(snap.usedFable)
        XCTAssertFalse(snap.fableIsActive)
    }

    func test_limits_scopedButDifferentModel_yieldsNilFable() async throws {
        // Guards against matching on `kind` alone: a future Opus weekly
        // limit must not be mistaken for Fable.
        let body = """
        {
            "five_hour": { "utilization": 26.0, "resets_at": "2026-08-13T15:09:59.783360+00:00" },
            "seven_day": { "utilization": 69.0, "resets_at": "2026-08-13T21:00:00.783384+00:00" },
            "limits": [
                { "kind": "weekly_scoped", "group": "weekly", "percent": 42,
                  "severity": "normal", "resets_at": "2026-08-13T20:59:59.783618+00:00",
                  "scope": { "model": { "id": null, "display_name": "Opus" }, "surface": null },
                  "is_active": true }
            ]
        }
        """
        let scraper = makeScraper(url: "https://claude.ai/api/scoped-opus", body: body)
        let snap = try await scraper.fetchSnapshot()
        XCTAssertNil(snap.usedFable)
        XCTAssertFalse(snap.fableIsActive)
    }

    func test_limits_malformedEntry_degradesToNilFable_keepsRestOfSnapshot() async throws {
        // `percent` is a string instead of a number on one entry — a
        // type change WITHIN limits[], not a missing/null key. Before
        // the fix, decoding `limits` inline on `Response` meant this
        // threw all the way out to ScrapeError.schemaDrift and blanked
        // 5h/Week too. Now limits[] is decoded separately with `try?`,
        // so this must degrade to "no Fable card" while 5h/Week still
        // come through fine.
        let body = """
        {
            "five_hour": { "utilization": 26.0, "resets_at": "2026-08-13T15:09:59.783360+00:00" },
            "seven_day": { "utilization": 69.0, "resets_at": "2026-08-13T21:00:00.783384+00:00" },
            "limits": [
                { "kind": "weekly_scoped", "group": "weekly", "percent": "not a number",
                  "severity": "critical", "resets_at": "2026-08-13T20:59:59.783618+00:00",
                  "scope": { "model": { "id": null, "display_name": "Fable" }, "surface": null },
                  "is_active": true }
            ]
        }
        """
        let scraper = makeScraper(url: "https://claude.ai/api/malformed-limits", body: body)
        let snap = try await scraper.fetchSnapshot()
        XCTAssertEqual(snap.used5h, 2600)
        XCTAssertEqual(snap.usedWeek, 6900)
        XCTAssertNil(snap.usedFable)
        XCTAssertNil(snap.resetTimeFable)
        XCTAssertFalse(snap.fableIsActive)
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
