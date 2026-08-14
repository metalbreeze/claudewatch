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

    func test_getBool_absentKey_returnsDefault() throws {
        let dbq = try DatabaseQueue()
        try Database.migrator.migrate(dbq)
        let repo = SettingsRepository(dbq: dbq)
        XCTAssertTrue(try repo.getBool(.menuBarShowFable, default: true))
        XCTAssertFalse(try repo.getBool(.menuBarShowWeek, default: false))
    }

    func test_setBoolThenGetBool_roundTrips() throws {
        let dbq = try DatabaseQueue()
        try Database.migrator.migrate(dbq)
        let repo = SettingsRepository(dbq: dbq)

        // Writing false must read back false even when the default is
        // true — this is the case a naive "any stored string is true"
        // parse would get wrong.
        try repo.setBool(.menuBarShow5h, false)
        XCTAssertFalse(try repo.getBool(.menuBarShow5h, default: true))

        try repo.setBool(.menuBarShow5h, true)
        XCTAssertTrue(try repo.getBool(.menuBarShow5h, default: false))
    }
}
