import XCTest
@testable import UsageCore

final class AlertEngineTests: XCTestCase {
    func test_5h_forecast_fires_when_projected_hit_within_15min_and_R2_high() {
        let now = Date()
        let snap = UsageSnapshot(timestamp: now, plan: .pro,
            used5h: 80_000, ceiling5h: 100_000,
            resetTime5h: now.addingTimeInterval(3600 * 4),
            usedWeek: 0, ceilingWeek: 1_000_000,
            resetTimeWeek: now.addingTimeInterval(86400),
            sourceVersion: "fake", raw: Data())
        let f = ForecastResult(slope: 1, intercept: 80_000,
            projectedHitTime: now.addingTimeInterval(600), line: [], rSquared: 0.9)
        let engine = AlertEngine()
        let fires = engine.decide(snapshot: snap, forecast: f, alertState: NoOpAlertState(), settings: .default, now: now)
        XCTAssertTrue(fires.contains(.fiveHourForecast))
    }

    func test_week_90_fires_at_threshold() {
        let now = Date()
        let snap = UsageSnapshot(timestamp: now, plan: .pro,
            used5h: 0, ceiling5h: 100_000, resetTime5h: now,
            usedWeek: 900_000, ceilingWeek: 1_000_000, resetTimeWeek: now,
            sourceVersion: "fake", raw: Data())
        let fires = AlertEngine().decide(snapshot: snap, forecast: nil, alertState: NoOpAlertState(),
                                          settings: .default, now: now)
        XCTAssertTrue(fires.contains(.weekNinety))
    }

    func test_dedup_within_same_5h_window() {
        let now = Date()
        let snap = UsageSnapshot(timestamp: now, plan: .pro,
            used5h: 90_000, ceiling5h: 100_000,
            resetTime5h: now.addingTimeInterval(3600),
            usedWeek: 0, ceilingWeek: 1_000_000, resetTimeWeek: now,
            sourceVersion: "fake", raw: Data())
        let f = ForecastResult(slope: 1, intercept: 90_000,
            projectedHitTime: now.addingTimeInterval(300), line: [], rSquared: 0.9)
        let state = StubAlertState()
        state.firedAt[.fiveHourForecast] = snap.currentWindowStart5h.addingTimeInterval(60)
        let fires = AlertEngine().decide(snapshot: snap, forecast: f, alertState: state, settings: .default, now: now)
        XCTAssertFalse(fires.contains(.fiveHourForecast))
    }
}

class StubAlertState: AlertStateReader {
    var firedAt: [AlertKind: Date] = [:]
    var snoozedUntil_: [AlertKind: Date] = [:]
    func lastFired(_ k: AlertKind) -> Date? { firedAt[k] }
    func snoozedUntil(_ k: AlertKind) -> Date? { snoozedUntil_[k] }
}
class NoOpAlertState: AlertStateReader {
    func lastFired(_ k: AlertKind) -> Date? { nil }
    func snoozedUntil(_ k: AlertKind) -> Date? { nil }
}
