import XCTest
@testable import UsageCore

final class PollingTimerTests: XCTestCase {
    func test_fires_at_expected_cadence() async {
        let timer = PollingTimer(interval: 0.2, jitter: 0)
        var ticks = 0
        let exp = expectation(description: "ticks")
        timer.onTick = { ticks += 1; if ticks == 3 { exp.fulfill() } }
        timer.start()
        await fulfillment(of: [exp], timeout: 2)
        timer.stop()
        XCTAssertEqual(ticks, 3)
    }
    func test_jitter_within_bounds() {
        let timer = PollingTimer(interval: 90, jitter: 10)
        for _ in 0..<100 {
            let next = timer.nextDelay()
            XCTAssertGreaterThanOrEqual(next, 80)
            XCTAssertLessThanOrEqual(next, 100)
        }
    }
}
