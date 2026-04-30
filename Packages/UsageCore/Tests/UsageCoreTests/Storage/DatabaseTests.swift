import XCTest
import GRDB
@testable import UsageCore

final class DatabaseTests: XCTestCase {
    func test_migration_creates_all_tables() throws {
        let dbq = try DatabaseQueue()
        try Database.migrator.migrate(dbq)
        try dbq.read { db in
            for t in ["snapshots", "snapshots_5min", "settings", "alert_state"] {
                XCTAssertTrue(try db.tableExists(t), "missing table \(t)")
            }
        }
    }
}
