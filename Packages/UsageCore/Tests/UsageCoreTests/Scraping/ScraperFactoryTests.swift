import XCTest
@testable import UsageCore

final class ScraperFactoryTests: XCTestCase {
    func test_returns_json_when_endpoint_is_set() {
        let cfg = EndpointConfig(jsonEndpoint: URL(string: "https://x")!)
        let pkg = CookiePackage(sessionKey: nil, cfClearance: nil, cfBm: nil, userAgent: "UA", all: [])
        let f = ScraperFactory(config: cfg, cookies: pkg)
        XCTAssertEqual(f.current().sourceVersion, "json-v2")
    }
    func test_falls_back_to_html_when_no_json_endpoint() {
        let cfg = EndpointConfig(jsonEndpoint: nil)
        let pkg = CookiePackage(sessionKey: nil, cfClearance: nil, cfBm: nil, userAgent: "UA", all: [])
        let f = ScraperFactory(config: cfg, cookies: pkg)
        XCTAssertEqual(f.current().sourceVersion, "html-v1")
    }
}
