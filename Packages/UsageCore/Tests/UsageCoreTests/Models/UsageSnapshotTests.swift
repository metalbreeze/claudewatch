import XCTest
@testable import UsageCore

final class UsageSnapshotTests: XCTestCase {
    func test_initialization_holds_all_fields() {
        let now = Date()
        let snap = UsageSnapshot(
            timestamp: now,
            plan: .pro,
            used5h: 12_000, ceiling5h: 100_000, resetTime5h: now.addingTimeInterval(3600 * 4),
            usedWeek: 50_000, ceilingWeek: 1_000_000, resetTimeWeek: now.addingTimeInterval(86400 * 5),
            sourceVersion: "json-v1",
            raw: Data("{}".utf8)
        )
        XCTAssertEqual(snap.used5h, 12_000)
        XCTAssertEqual(snap.fraction5h, 0.12, accuracy: 0.0001)
        XCTAssertEqual(snap.fractionWeek, 0.05, accuracy: 0.0001)
    }
    func test_fraction_clamps_at_one() {
        let now = Date()
        let snap = UsageSnapshot(
            timestamp: now, plan: .pro,
            used5h: 200_000, ceiling5h: 100_000, resetTime5h: now,
            usedWeek: 0, ceilingWeek: 1, resetTimeWeek: now,
            sourceVersion: "json-v1", raw: Data()
        )
        XCTAssertEqual(snap.fraction5h, 1.0)
    }
}
