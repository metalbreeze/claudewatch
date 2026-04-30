import XCTest
import GRDB
@testable import UsageCore

final class AlertStateRepositoryTests: XCTestCase {
    func test_recordFire_updates_lastFiredAt() throws {
        let dbq = try DatabaseQueue(); try Database.migrator.migrate(dbq)
        let repo = AlertStateRepository(dbq: dbq)
        let t = Date()
        try repo.recordFire(.fiveHourForecast, at: t)
        XCTAssertEqual(try repo.lastFired(.fiveHourForecast)!.timeIntervalSince1970,
                       t.timeIntervalSince1970, accuracy: 1)
    }
    func test_snooze_persists() throws {
        let dbq = try DatabaseQueue(); try Database.migrator.migrate(dbq)
        let repo = AlertStateRepository(dbq: dbq)
        let until = Date().addingTimeInterval(3600)
        try repo.snooze(.fiveHourForecast, until: until)
        XCTAssertEqual(try repo.snoozedUntil(.fiveHourForecast)!.timeIntervalSince1970,
                       until.timeIntervalSince1970, accuracy: 1)
    }
}
