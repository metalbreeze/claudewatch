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
}
struct FakeScraper: UsageScraper {
    let sourceVersion = "fake"
    let snap: UsageSnapshot
    func fetchSnapshot() async throws -> UsageSnapshot { snap }
}
