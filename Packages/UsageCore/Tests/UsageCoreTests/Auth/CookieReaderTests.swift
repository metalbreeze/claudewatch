import XCTest
@testable import UsageCore

final class CookieReaderTests: XCTestCase {
    func test_packageCookies_serializes_known_names() {
        let session = HTTPCookie(properties: [
            .name: "sessionKey", .value: "abc", .domain: ".claude.ai", .path: "/"])!
        let cf = HTTPCookie(properties: [
            .name: "cf_clearance", .value: "xyz", .domain: ".claude.ai", .path: "/"])!
        let stranger = HTTPCookie(properties: [
            .name: "_ga", .value: "ignored", .domain: ".claude.ai", .path: "/"])!
        let pkg = CookieReader.package(from: [session, cf, stranger], userAgent: "TestUA/1.0")
        XCTAssertEqual(pkg.sessionKey, "abc")
        XCTAssertEqual(pkg.cfClearance, "xyz")
        XCTAssertEqual(pkg.userAgent, "TestUA/1.0")
        // _ga is dropped from the typed package but present in `all`
        XCTAssertEqual(pkg.all.count, 3)
    }
}
