import XCTest
@testable import UsageCore

final class BaselineForecasterTests: XCTestCase {
    func test_returns_24_buckets_for_24h_mode() {
        let now = Date()
        // 5 days of synthetic snapshots, one per hour
        var snaps: [UsageSnapshot] = []
        let cal = Calendar(identifier: .gregorian)
        for d in 1...5 {
            for h in 0..<24 {
                var c = cal.dateComponents([.year,.month,.day], from: now)
                c.day = (c.day ?? 1) - d; c.hour = h; c.minute = 0
                let t = cal.date(from: c)!
                snaps.append(UsageSnapshot(timestamp: t, plan: .pro,
                    used5h: h * 1000, ceiling5h: 100_000, resetTime5h: t,
                    usedWeek: 0, ceilingWeek: 1_000_000, resetTimeWeek: t,
                    sourceVersion: "json-v1", raw: Data()))
            }
        }
        let r = BaselineForecaster().baseline(snapshots: snaps, mode: .twentyFourHour, now: now)
        XCTAssertEqual(r.buckets.count, 24)
        // bucket 0 should have median ~0, bucket 23 should have median ~0.23
        XCTAssertEqual(r.buckets[0].median, 0, accuracy: 0.01)
        XCTAssertEqual(r.buckets[23].median, 0.23, accuracy: 0.01)
    }

    func test_returns_empty_when_history_too_short() {
        let r = BaselineForecaster().baseline(snapshots: [], mode: .twentyFourHour)
        XCTAssertTrue(r.buckets.isEmpty)
        XCTAssertEqual(r.note, .insufficientHistory)
    }
}
