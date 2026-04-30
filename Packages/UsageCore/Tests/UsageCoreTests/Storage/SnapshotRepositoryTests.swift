import XCTest
import GRDB
@testable import UsageCore

final class SnapshotRepositoryTests: XCTestCase {
    var dbq: DatabaseQueue!
    var repo: SnapshotRepository!

    override func setUp() {
        dbq = try! DatabaseQueue()
        try! Database.migrator.migrate(dbq)
        repo = SnapshotRepository(dbq: dbq, deviceID: "test-device")
    }

    func test_insert_then_fetchRecent_returns_inserted_rows() throws {
        let now = Date()
        let snap = makeSnap(ts: now)
        try repo.insert(snap)
        let recent = try repo.fetchRecent(within: 60 * 60)
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent[0].used5h, snap.used5h)
    }

    func test_fetchRecent_excludes_old_rows() throws {
        try repo.insert(makeSnap(ts: Date().addingTimeInterval(-7200)))
        try repo.insert(makeSnap(ts: Date()))
        let recent = try repo.fetchRecent(within: 3600)
        XCTAssertEqual(recent.count, 1)
    }

    private func makeSnap(ts: Date) -> UsageSnapshot {
        UsageSnapshot(timestamp: ts, plan: .pro,
            used5h: 1000, ceiling5h: 100_000, resetTime5h: ts.addingTimeInterval(3600 * 4),
            usedWeek: 5000, ceilingWeek: 1_000_000, resetTimeWeek: ts.addingTimeInterval(86400 * 5),
            sourceVersion: "json-v1", raw: Data())
    }
}
