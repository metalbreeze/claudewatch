import XCTest
@testable import UsageCore

final class HeatmapBucketingTests: XCTestCase {
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Helper: build a snapshot whose only meaningful field for these
    /// tests is `timestamp` and `used5h / ceiling5h`.
    private func snap(at iso: String, used: Int = 50, ceiling: Int = 100) -> UsageSnapshot {
        guard let t = Self.isoFormatter.date(from: iso) else {
            XCTFail("Bad ISO date string: \(iso)")
            return UsageSnapshot(timestamp: Date(), plan: .pro,
                                 used5h: 0, ceiling5h: 1,
                                 resetTime5h: Date(),
                                 usedWeek: 0, ceilingWeek: 1,
                                 resetTimeWeek: Date(),
                                 sourceVersion: "test", raw: Data())
        }
        return UsageSnapshot(
            timestamp: t, plan: .pro,
            used5h: used, ceiling5h: ceiling,
            resetTime5h: t.addingTimeInterval(3600),
            usedWeek: 0, ceilingWeek: 1_000_000,
            resetTimeWeek: t,
            sourceVersion: "test", raw: Data())
    }

    private func parseUTC(_ s: String) -> Date {
        Self.isoFormatter.date(from: s)!
    }

    private let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    func test_emptySnapshots_returnsEmptyMap() {
        let result = HeatmapBucket.bucketize([], now: Date(), calendar: utcCalendar)
        XCTAssertTrue(result.isEmpty)
    }

    func test_singleSnapshot_inCorrectBucket() {
        // Snapshot at 2026-05-06 14:23 UTC, "now" is the same day at 23:59.
        // dayDelta = 0 → dayIndex = 27. hour = 14 → slotIndex = 14/4 = 3.
        let now = parseUTC("2026-05-06T23:59:00Z")
        let s = snap(at: "2026-05-06T14:23:00Z", used: 50, ceiling: 100)
        let result = HeatmapBucket.bucketize([s], now: now, calendar: utcCalendar)
        let key = HeatmapBucket(dayIndex: 27, slotIndex: 3)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[key] ?? 0, 0.5, accuracy: 0.001)
    }

    func test_takesMaxNotAverage() {
        // Three snapshots in the same (day, slot) at 30%, 60%, 45%.
        // Result should be 0.60 (max), not 0.45 (avg).
        let now = parseUTC("2026-05-06T23:59:00Z")
        let snaps = [
            snap(at: "2026-05-06T13:00:00Z", used: 30, ceiling: 100),
            snap(at: "2026-05-06T13:30:00Z", used: 60, ceiling: 100),
            snap(at: "2026-05-06T14:00:00Z", used: 45, ceiling: 100),
        ]
        let result = HeatmapBucket.bucketize(snaps, now: now, calendar: utcCalendar)
        let key = HeatmapBucket(dayIndex: 27, slotIndex: 3)
        XCTAssertEqual(result[key] ?? 0, 0.60, accuracy: 0.001)
    }

    func test_dropsSnapshotsOlderThan28Days() {
        // Snapshot at -29 days excluded; -27 days included.
        let now = parseUTC("2026-05-06T12:00:00Z")
        let oldSnap   = snap(at: "2026-04-07T12:00:00Z")  // -29 days ago
        let validSnap = snap(at: "2026-04-09T12:00:00Z")  // -27 days ago
        let result = HeatmapBucket.bucketize([oldSnap, validSnap],
                                             now: now,
                                             calendar: utcCalendar)
        XCTAssertEqual(result.count, 1)
        // Real check: nothing in the result has an out-of-range dayIndex.
        XCTAssertTrue(result.keys.allSatisfy { (0..<HeatmapBucket.dayCount).contains($0.dayIndex) })
        XCTAssertNotNil(result[HeatmapBucket(dayIndex: 0, slotIndex: 3)])
    }

    func test_dayBoundaryAtMidnight() {
        // Snapshot at 2026-05-06 23:59:59 lands in slotIndex 5 (20-24).
        // Snapshot 2 seconds later (2026-05-07 00:00:01) lands in
        // slotIndex 0 of the next day.
        let now = parseUTC("2026-05-07T12:00:00Z")
        let lateSnap  = snap(at: "2026-05-06T23:59:59Z")
        let earlySnap = snap(at: "2026-05-07T00:00:01Z")
        let result = HeatmapBucket.bucketize([lateSnap, earlySnap], now: now, calendar: utcCalendar)
        // Late snap: 1 day before now → dayIndex = 26. slot = 23/4 = 5.
        XCTAssertNotNil(result[HeatmapBucket(dayIndex: 26, slotIndex: 5)])
        // Early snap: same day as now → dayIndex = 27. slot = 0/4 = 0.
        XCTAssertNotNil(result[HeatmapBucket(dayIndex: 27, slotIndex: 0)])
    }
}
