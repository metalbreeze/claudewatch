import XCTest
import GRDB
@testable import UsageCore

final class SettingsRepositoryTests: XCTestCase {
    func test_set_then_get_returns_value() throws {
        let dbq = try DatabaseQueue()
        try Database.migrator.migrate(dbq)
        let repo = SettingsRepository(dbq: dbq)
        try repo.set(.selectedTimeframe, "8h")
        XCTAssertEqual(try repo.get(.selectedTimeframe), "8h")
    }
    func test_get_missing_key_returns_nil() throws {
        let dbq = try DatabaseQueue()
        try Database.migrator.migrate(dbq)
        let repo = SettingsRepository(dbq: dbq)
        XCTAssertNil(try repo.get(.theme))
    }
}
