import XCTest
import GRDB
@testable import UsageCore

final class UsageControllerTests: XCTestCase {
    func test_poll_inserts_snapshot_and_publishes_state() async throws {
        let dbq = try DatabaseQueue(); try Database.migrator.migrate(dbq)
        let snap = UsageSnapshot(timestamp: Date(), plan: .pro,
            used5h: 1, ceiling5h: 100, resetTime5h: Date().addingTimeInterval(3600),
            usedWeek: 1, ceilingWeek: 1000, resetTimeWeek: Date().addingTimeInterval(86400*5),
            sourceVersion: "fake", raw: Data())

        let controller = await UsageController(
            scraper: FakeScraper(snap: snap),
            snapshots: SnapshotRepository(dbq: dbq, deviceID: "d1"),
            forecaster: LinearForecaster()
        )
        try await controller.pollOnce()
        let latest = await controller.state.latest
        XCTAssertNotNil(latest)
        XCTAssertEqual(latest?.used5h, 1)
    }

    func test_sync_called_at_most_once_per_300s() async throws {
        let dbq = try DatabaseQueue(); try Database.migrator.migrate(dbq)
        let snap = UsageSnapshot(timestamp: Date(), plan: .pro,
            used5h: 1, ceiling5h: 100, resetTime5h: Date(),
            usedWeek: 1, ceilingWeek: 1000, resetTimeWeek: Date(),
            sourceVersion: "fake", raw: Data())
        let sync = SpySync()
        let controller = await UsageController(
            scraper: FakeScraper(snap: snap),
            snapshots: SnapshotRepository(dbq: dbq, deviceID: "d1"),
            forecaster: LinearForecaster(),
            sync: sync,
            syncIntervalSeconds: 1) // shorten for test
        try await controller.pollOnce()
        try await controller.pollOnce()
        try await Task.sleep(nanoseconds: 1_200_000_000)
        try await controller.pollOnce()
        XCTAssertEqual(sync.calls, 2, "first poll + post-1s")
    }

    func test_snapshots_within_timeframe() async throws {
        let dbq = try DatabaseQueue(); try Database.migrator.migrate(dbq)
        let snap = UsageSnapshot(timestamp: Date(), plan: .pro,
            used5h: 1, ceiling5h: 100, resetTime5h: Date(),
            usedWeek: 1, ceilingWeek: 1000, resetTimeWeek: Date(),
            sourceVersion: "fake", raw: Data())
        let c = await UsageController(scraper: FakeScraper(snap: snap),
                                snapshots: SnapshotRepository(dbq: dbq, deviceID: "d1"),
                                forecaster: LinearForecaster())
        try await c.pollOnce()
        let arr = try await c.snapshots(within: 60 * 60)
        XCTAssertEqual(arr.count, 1)
    }
}
struct FakeScraper: UsageScraper {
    let sourceVersion = "fake"
    let snap: UsageSnapshot
    func fetchSnapshot() async throws -> UsageSnapshot { snap }
}

final class SpySync: CloudKitSyncing {
    var calls = 0
    func uploadPending(snapshots: [UsageSnapshot]) async throws { calls += 1 }
}
