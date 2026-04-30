import XCTest
@testable import UsageCore

final class UsageCoreSentinelTests: XCTestCase {
    func test_version_is_set() {
        XCTAssertEqual(UsageCore.version, "0.1.0")
    }
}
