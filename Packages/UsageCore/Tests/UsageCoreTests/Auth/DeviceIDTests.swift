import XCTest
@testable import UsageCore

final class DeviceIDTests: XCTestCase {
    func test_first_call_generates_id_subsequent_returns_same() throws {
        let store = InMemoryKeychain()
        let id1 = try DeviceID.getOrCreate(in: store)
        let id2 = try DeviceID.getOrCreate(in: store)
        XCTAssertEqual(id1, id2)
        XCTAssertFalse(id1.isEmpty)
    }
}
final class InMemoryKeychain: KeychainStoring {
    var dict: [String: Data] = [:]
    func read(service: String, account: String) throws -> Data? { dict["\(service)/\(account)"] }
    func write(service: String, account: String, data: Data) throws { dict["\(service)/\(account)"] = data }
    func delete(service: String, account: String) throws { dict["\(service)/\(account)"] = nil }
}
