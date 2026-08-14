import XCTest
@testable import UsageCore

final class MenuBarFormatterTests: XCTestCase {
    /// 26% / 69% / 99% on the 0–10000 scale the scrapers use.
    private func snap(fable: Int? = 9900) -> UsageSnapshot {
        let t = Date(timeIntervalSince1970: 1_770_000_000)
        return UsageSnapshot(
            timestamp: t, plan: .pro,
            used5h: 2600, ceiling5h: 10_000, resetTime5h: t.addingTimeInterval(3600),
            usedWeek: 6900, ceilingWeek: 10_000, resetTimeWeek: t.addingTimeInterval(86_400),
            sourceVersion: "test", raw: Data(),
            usedFable: fable,
            resetTimeFable: fable == nil ? nil : t.addingTimeInterval(86_400),
            fableIsActive: fable != nil)
    }

    private func opts(_ five: Bool, _ week: Bool, _ fable: Bool, _ labels: Bool)
        -> MenuBarDisplayOptions {
        MenuBarDisplayOptions(show5h: five, showWeek: week,
                              showFable: fable, showLabels: labels)
    }

    func test_allThreeWithLabels() {
        let s = MenuBarFormatter.segments(snapshot: snap(),
                                          options: opts(true, true, true, true))
        XCTAssertEqual(s, "5h:26%/1w:69%/F:99%")
    }

    func test_allThreeWithoutLabels() {
        let s = MenuBarFormatter.segments(snapshot: snap(),
                                          options: opts(true, true, true, false))
        XCTAssertEqual(s, "26%/69%/99%")
    }

    func test_fableAbsent_dropsSegmentEntirely() {
        // No trailing slash, no "F:0%" — the account simply has no
        // Fable quota, which is not the same as having used none of it.
        let s = MenuBarFormatter.segments(snapshot: snap(fable: nil),
                                          options: opts(true, true, true, true))
        XCTAssertEqual(s, "5h:26%/1w:69%")
    }

    func test_nothingSelected_returnsEmpty() {
        let s = MenuBarFormatter.segments(snapshot: snap(),
                                          options: opts(false, false, false, false))
        XCTAssertEqual(s, "")
    }

    func test_nilSnapshot_returnsEmpty() {
        let s = MenuBarFormatter.segments(snapshot: nil,
                                          options: opts(true, true, true, true))
        XCTAssertEqual(s, "")
    }

    func test_singleSegmentNoLabel_hasNoStraySeparator() {
        let s = MenuBarFormatter.segments(snapshot: snap(),
                                          options: opts(true, false, false, false))
        XCTAssertEqual(s, "26%")
    }

    func test_orderIsFixedRegardlessOfSelection() {
        // 5h is skipped, but 1w must still precede F.
        let s = MenuBarFormatter.segments(snapshot: snap(),
                                          options: opts(false, true, true, true))
        XCTAssertEqual(s, "1w:69%/F:99%")
    }

    func test_defaultOptions() {
        // Documented default: 5h + Fable + labels, weekly off.
        let d = MenuBarDisplayOptions.default
        XCTAssertTrue(d.show5h)
        XCTAssertFalse(d.showWeek)
        XCTAssertTrue(d.showFable)
        XCTAssertTrue(d.showLabels)
        XCTAssertEqual(MenuBarFormatter.segments(snapshot: snap(), options: d),
                       "5h:26%/F:99%")
    }
}
