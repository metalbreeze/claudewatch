import XCTest
@testable import UsageCore

final class ScrapeErrorTests: XCTestCase {
    func test_error_categories() {
        XCTAssertTrue(ScrapeError.authExpired.isAuthRelated)
        XCTAssertTrue(ScrapeError.cloudflareChallenge.requiresWebViewRefresh)
        XCTAssertFalse(ScrapeError.network(URLError(.timedOut)).isAuthRelated)
    }
}
