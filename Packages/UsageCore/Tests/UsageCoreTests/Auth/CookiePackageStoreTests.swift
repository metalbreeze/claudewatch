import XCTest
@testable import UsageCore

final class CookiePackageStoreTests: XCTestCase {
    func test_save_then_load_roundtrips() throws {
        let kc = InMemoryKeychain()
        let pkg = CookiePackage(sessionKey: "s", cfClearance: "c", cfBm: nil,
                                userAgent: "UA", all: [])
        try CookiePackageStore(keychain: kc, deviceID: "d1").save(pkg)
        let loaded = try CookiePackageStore(keychain: kc, deviceID: "d1").load()
        XCTAssertEqual(loaded?.sessionKey, "s")
    }
}
