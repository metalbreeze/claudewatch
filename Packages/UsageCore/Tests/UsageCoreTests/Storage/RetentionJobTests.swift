import XCTest
import GRDB
@testable import UsageCore

final class RetentionJobTests: XCTestCase {
    func test_rows_older_than_7_days_collapse_into_5min_buckets() throws {
        let dbq = try DatabaseQueue(); try Database.migrator.migrate(dbq)
        let repo = SnapshotRepository(dbq: dbq, deviceID: "d1")
        // Align to a 5-min bucket boundary so all 5 snapshots (spanning 4 min) land in one bucket.
        let rawOld = Date().addingTimeInterval(-86400 * 8)
        let aligned = TimeInterval(Int(rawOld.timeIntervalSince1970 / 300) * 300)
        let oldTs = Date(timeIntervalSince1970: aligned)
        for i in 0..<5 {
            try repo.insert(makeSnap(ts: oldTs.addingTimeInterval(Double(i) * 60), used5h: 1000 + i*10))
        }
        let job = RetentionJob(dbq: dbq)
        try job.run(now: Date())
        let buckets = try dbq.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM snapshots_5min")
        }
        XCTAssertEqual(buckets.count, 1)
        XCTAssertEqual(buckets[0]["bucket_count"] as Int64, 5)
        let raw = try dbq.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM snapshots WHERE ts < ?",
                             arguments: [Int(Date().addingTimeInterval(-86400*7).timeIntervalSince1970)])!
        }
        XCTAssertEqual(raw, 0, "old raw rows should be deleted")
    }

    func test_rows_in_last_7_days_are_untouched() throws {
        let dbq = try DatabaseQueue(); try Database.migrator.migrate(dbq)
        let repo = SnapshotRepository(dbq: dbq, deviceID: "d1")
        try repo.insert(makeSnap(ts: Date(), used5h: 5000))
        let job = RetentionJob(dbq: dbq)
        try job.run(now: Date())
        XCTAssertEqual(try repo.fetchRecent(within: 60).count, 1)
    }

    private func makeSnap(ts: Date, used5h: Int) -> UsageSnapshot {
        UsageSnapshot(timestamp: ts, plan: .pro,
            used5h: used5h, ceiling5h: 100_000, resetTime5h: ts,
            usedWeek: 0, ceilingWeek: 1_000_000, resetTimeWeek: ts,
            sourceVersion: "json-v1", raw: Data())
    }
}
