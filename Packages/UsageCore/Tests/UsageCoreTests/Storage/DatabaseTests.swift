import XCTest
import GRDB
@testable import UsageCore

final class DatabaseTests: XCTestCase {
    func test_migration_creates_all_tables() throws {
        let dbq = try DatabaseQueue()
        try Database.migrator.migrate(dbq)
        try dbq.read { db in
            for t in ["snapshots", "settings", "alert_state"] {
                XCTAssertTrue(try db.tableExists(t), "missing table \(t)")
            }
        }
    }

    /// Guards the v3 removal rather than merely tolerating it.
    ///
    /// `snapshots_5min` was the storage half of a retention design that
    /// never shipped, and reviving it would now delete data the 1-month
    /// heatmap depends on — it reads 28 days of raw snapshots, while that
    /// design pruned raw rows at 7 days. Dropping the assertion instead of
    /// inverting it would let the table quietly come back.
    func test_migration_removes_the_vestigial_rollup_table() throws {
        let dbq = try DatabaseQueue()
        try Database.migrator.migrate(dbq)
        try dbq.read { db in
            XCTAssertFalse(try db.tableExists("snapshots_5min"),
                           "snapshots_5min is intentionally dropped in v3 — see Database.swift")
        }
    }
}
