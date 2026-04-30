import XCTest
@testable import UsageCore

final class ForecastResultTests: XCTestCase {
    func test_lowConfidence_when_R2_below_threshold() {
        let r = ForecastResult(slope: 1, intercept: 0, projectedHitTime: nil, line: [], rSquared: 0.3)
        XCTAssertTrue(r.isLowConfidence)
    }
    func test_highConfidence_when_R2_above_threshold() {
        let r = ForecastResult(slope: 1, intercept: 0, projectedHitTime: nil, line: [], rSquared: 0.7)
        XCTAssertFalse(r.isLowConfidence)
    }
}
