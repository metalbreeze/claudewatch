import XCTest
@testable import UsageCore

final class LinearForecasterTests: XCTestCase {
    func test_perfect_line_predicts_hit_at_correct_time() {
        let now = Date()
        var snaps: [UsageSnapshot] = []
        for i in 0..<10 {
            let t = now.addingTimeInterval(-Double(60 - i*6))
            let used = i * 1000
            snaps.append(UsageSnapshot(
                timestamp: t, plan: .pro,
                used5h: used, ceiling5h: 100_000,
                resetTime5h: now.addingTimeInterval(3600 * 4),
                usedWeek: 0, ceilingWeek: 1_000_000,
                resetTimeWeek: now,
                sourceVersion: "json-v1", raw: Data()))
        }
        let result = LinearForecaster().forecast(snapshots: snaps, now: now)!
        XCTAssertGreaterThan(result.slope, 0)
        XCTAssertGreaterThan(result.rSquared, 0.95)
        XCTAssertNotNil(result.projectedHitTime)
    }

    func test_returns_nil_with_fewer_than_3_points() {
        let r = LinearForecaster().forecast(snapshots: [], now: Date())
        XCTAssertNil(r)
    }

    func test_negative_slope_yields_nil_projectedHitTime() {
        let now = Date()
        let snaps = (0..<5).map { i -> UsageSnapshot in
            UsageSnapshot(timestamp: now.addingTimeInterval(-Double(60 - i*15)),
                          plan: .pro,
                          used5h: max(1000, 5000 - i*800), ceiling5h: 100_000,
                          resetTime5h: now.addingTimeInterval(3600),
                          usedWeek: 0, ceilingWeek: 1_000_000, resetTimeWeek: now,
                          sourceVersion: "json-v1", raw: Data())
        }
        let r = LinearForecaster().forecast(snapshots: snaps, now: now)!
        XCTAssertNil(r.projectedHitTime)
    }
}
