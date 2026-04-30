import XCTest
@testable import UsageCore

final class PlanTests: XCTestCase {
    func test_known_plan_strings_decode_correctly() {
        XCTAssertEqual(Plan(rawString: "Pro"), .pro)
        XCTAssertEqual(Plan(rawString: "Max 5x"), .max5x)
        XCTAssertEqual(Plan(rawString: "Max 20x"), .max20x)
        XCTAssertEqual(Plan(rawString: "Team"), .team)
        XCTAssertEqual(Plan(rawString: "Free"), .free)
    }
    func test_unknown_string_becomes_custom() {
        XCTAssertEqual(Plan(rawString: "Enterprise"), .custom("Enterprise"))
    }
    func test_displayName() {
        XCTAssertEqual(Plan.pro.displayName, "Pro")
        XCTAssertEqual(Plan.custom("Enterprise").displayName, "Enterprise")
    }
}
