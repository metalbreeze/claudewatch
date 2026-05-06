import Foundation

/// Coordinate of a single cell in the 1-month heatmap.
///
/// `dayIndex`: 0 = `dayCount-1` days ago, `dayCount-1` = today (according
/// to the caller-supplied `now`).
///
/// `slotIndex`: 0..5, where each slot covers 4 hours of local
/// wall-clock time. Slot 0 covers 00:00:00–03:59:59, slot 5 covers
/// 20:00:00–23:59:59.
public struct HeatmapBucket: Hashable {
    public let dayIndex: Int
    public let slotIndex: Int

    /// Number of days the heatmap covers. The grid is laid out
    /// horizontally with column 0 = oldest, column dayCount-1 = today.
    public static let dayCount = 28

    /// Hours per time-of-day slot. 4 hours × 6 slots = 24-hour day.
    public static let slotHours = 4

    public init(dayIndex: Int, slotIndex: Int) {
        self.dayIndex = dayIndex
        self.slotIndex = slotIndex
    }

    /// Bucketize snapshots into a (day, 4-hour-slot) grid keyed by
    /// `HeatmapBucket`. The cell value is the **maximum** `fraction5h`
    /// observed in that bucket — see spec
    /// `docs/superpowers/specs/2026-05-06-onemonth-heatmap-design.md`
    /// for why max instead of average.
    ///
    /// Snapshots whose timestamp falls outside the [now − 28 days, now]
    /// window are silently dropped.
    ///
    /// `calendar` defaults to `Calendar.current` so day/slot boundaries
    /// reflect the user's local timezone — "08:00–12:00" means the user's
    /// morning, not 08–12 UTC. The parameter is exposed primarily so
    /// tests can pass a UTC-fixed calendar for deterministic assertions
    /// across machines.
    public static func bucketize(
        _ snapshots: [UsageSnapshot],
        now: Date,
        calendar: Calendar = Calendar.current
    ) -> [HeatmapBucket: Double] {
        var maxFraction: [HeatmapBucket: Double] = [:]
        let todayMidnight = calendar.startOfDay(for: now)

        for s in snapshots {
            let snapMidnight = calendar.startOfDay(for: s.timestamp)
            let dayDelta = calendar.dateComponents([.day],
                                               from: snapMidnight,
                                               to: todayMidnight).day ?? 0
            let dayIndex = (dayCount - 1) - dayDelta
            guard (0..<dayCount).contains(dayIndex) else { continue }

            let hour = calendar.component(.hour, from: s.timestamp)
            let key = HeatmapBucket(dayIndex: dayIndex, slotIndex: hour / slotHours)
            maxFraction[key] = max(maxFraction[key] ?? 0, s.fraction5h)
        }
        return maxFraction
    }
}
