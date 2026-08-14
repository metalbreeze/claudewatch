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

    func test_insertAndFetch_roundTripsFableFields() throws {
        let repo = SnapshotRepository(dbq: dbq, deviceID: "dev")
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let fableReset = Date(timeIntervalSince1970: 1_770_050_000)
        let snap = UsageSnapshot(
            timestamp: now, plan: .pro,
            used5h: 2600, ceiling5h: 10_000, resetTime5h: now.addingTimeInterval(3600),
            usedWeek: 6900, ceilingWeek: 10_000, resetTimeWeek: now.addingTimeInterval(86_400),
            sourceVersion: "json-v2", raw: Data(),
            usedFable: 9900, resetTimeFable: fableReset, fableIsActive: true)
        try repo.insert(snap)

        let got = try repo.mostRecent()
        XCTAssertEqual(got?.usedFable, 9900)
        let gotResetFable = try XCTUnwrap(got?.resetTimeFable?.timeIntervalSince1970)
        XCTAssertEqual(gotResetFable, fableReset.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(got?.fableIsActive, true)
    }

    func test_insertWithoutFable_readsBackAsNil() throws {
        // Mirrors both a Fable-less account AND any row written by a
        // build predating migration v2.
        let repo = SnapshotRepository(dbq: dbq, deviceID: "dev")
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let snap = UsageSnapshot(
            timestamp: now, plan: .pro,
            used5h: 2600, ceiling5h: 10_000, resetTime5h: now.addingTimeInterval(3600),
            usedWeek: 6900, ceilingWeek: 10_000, resetTimeWeek: now.addingTimeInterval(86_400),
            sourceVersion: "json-v2", raw: Data())
        try repo.insert(snap)

        let got = try repo.mostRecent()
        XCTAssertNotNil(got)
        XCTAssertNil(got?.usedFable)
        XCTAssertNil(got?.resetTimeFable)
        XCTAssertEqual(got?.fableIsActive, false)
    }
}
