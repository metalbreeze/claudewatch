# 1-Month Heatmap & Timeframe Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `1h` chart timeframe with a `1m` four-week heatmap view (6 four-hour slots × 28 days, Canvas-rendered).

**Architecture:** Bucketing logic lives in `UsageCore` (testable, platform-agnostic). The Mac app's `Popover/` directory gains a `HeatmapView.swift` (Canvas renderer) and `HeatmapPalette.swift` (color scale). The existing `ChartView.swift` is renamed `LineChartView.swift`; `PopoverRootView` switches between the two views based on `timeframe == .oneMonth`. Chart frame height grows from 90 pt to 140 pt uniformly across all four tabs to avoid layout jumping when switching.

**Tech Stack:** Swift 5.10, SwiftUI Canvas, XCTest, XcodeGen (`project.yml` is the source of truth — never edit `.xcodeproj` directly).

**Spec:** `docs/superpowers/specs/2026-05-06-onemonth-heatmap-design.md`

**Spec deviation note:** The spec puts the bucketing function inside `HeatmapView.swift` (Mac app target). The plan instead places it in the `UsageCore` Swift package so it can be unit-tested from `UsageCoreTests` (the only test target). The split is: pure data logic in `UsageCore`, view rendering + color in the Mac app. This honors the spec's testing requirements while keeping responsibilities clean.

---

## Task 1: Add `HeatmapBucket` model + `bucketize` function in `UsageCore` (TDD)

**Files:**
- Create: `Packages/UsageCore/Sources/UsageCore/Heatmap/HeatmapBucket.swift`
- Create: `Packages/UsageCore/Tests/UsageCoreTests/Heatmap/HeatmapBucketingTests.swift`

- [ ] **Step 1: Create the test file with all 5 failing tests**

Create `Packages/UsageCore/Tests/UsageCoreTests/Heatmap/HeatmapBucketingTests.swift`:

```swift
import XCTest
@testable import UsageCore

final class HeatmapBucketingTests: XCTestCase {
    /// Helper: build a snapshot whose only meaningful field for these
    /// tests is `timestamp` and `used5h / ceiling5h`.
    private func snap(at iso: String, used: Int = 50, ceiling: Int = 100) -> UsageSnapshot {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let t = f.date(from: iso) ?? f.date(from: iso + ".000Z") ?? Date()
        return UsageSnapshot(
            timestamp: t, plan: .pro,
            used5h: used, ceiling5h: ceiling,
            resetTime5h: t.addingTimeInterval(3600),
            usedWeek: 0, ceilingWeek: 1_000_000,
            resetTimeWeek: t,
            sourceVersion: "test", raw: Data())
    }

    private func parseUTC(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)!
    }

    func test_emptySnapshots_returnsEmptyMap() {
        let result = HeatmapBucket.bucketize([], now: Date())
        XCTAssertTrue(result.isEmpty)
    }

    func test_singleSnapshot_inCorrectBucket() {
        // Snapshot at 2026-05-06 14:23 UTC, "now" is the same day at 23:59.
        // dayDelta = 0 → dayIndex = 27. hour = 14 → slotIndex = 14/4 = 3.
        let now = parseUTC("2026-05-06T23:59:00Z")
        let s = snap(at: "2026-05-06T14:23:00Z", used: 50, ceiling: 100)
        let result = HeatmapBucket.bucketize([s], now: now)
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
        let result = HeatmapBucket.bucketize(snaps, now: now)
        let key = HeatmapBucket(dayIndex: 27, slotIndex: 3)
        XCTAssertEqual(result[key] ?? 0, 0.60, accuracy: 0.001)
    }

    func test_dropsSnapshotsOlderThan28Days() {
        // Snapshot at -29 days excluded; -27 days included.
        let now = parseUTC("2026-05-06T12:00:00Z")
        let oldSnap   = snap(at: "2026-04-07T12:00:00Z")  // -29 days ago
        let validSnap = snap(at: "2026-04-09T12:00:00Z")  // -27 days ago
        let result = HeatmapBucket.bucketize([oldSnap, validSnap], now: now)
        XCTAssertEqual(result.count, 1)
        XCTAssertNil(result[HeatmapBucket(dayIndex: -1, slotIndex: 3)])
        XCTAssertNotNil(result[HeatmapBucket(dayIndex: 1, slotIndex: 3)])
    }

    func test_dayBoundaryAtMidnight() {
        // Snapshot at 2026-05-06 23:59:59 lands in slotIndex 5 (20-24).
        // Snapshot 2 seconds later (2026-05-07 00:00:01) lands in
        // slotIndex 0 of the next day.
        let now = parseUTC("2026-05-07T12:00:00Z")
        let lateSnap  = snap(at: "2026-05-06T23:59:59Z")
        let earlySnap = snap(at: "2026-05-07T00:00:01Z")
        let result = HeatmapBucket.bucketize([lateSnap, earlySnap], now: now)
        // Late snap: 1 day before now → dayIndex = 26. slot = 23/4 = 5.
        XCTAssertNotNil(result[HeatmapBucket(dayIndex: 26, slotIndex: 5)])
        // Early snap: same day as now → dayIndex = 27. slot = 0/4 = 0.
        XCTAssertNotNil(result[HeatmapBucket(dayIndex: 27, slotIndex: 0)])
    }
}
```

- [ ] **Step 2: Run tests, confirm all 5 fail with "no such type 'HeatmapBucket'"**

```bash
cd Packages/UsageCore && swift test --filter HeatmapBucketingTests 2>&1 | tail -20
```

Expected: FAIL — `cannot find 'HeatmapBucket' in scope` or similar.

- [ ] **Step 3: Implement the model + function**

Create `Packages/UsageCore/Sources/UsageCore/Heatmap/HeatmapBucket.swift`:

```swift
import Foundation

/// Coordinate of a single cell in the 1-month heatmap.
///
/// `dayIndex`: 0 = 28 days ago, 27 = today (according to the
/// caller-supplied `now`).
///
/// `slotIndex`: 0..5, where each slot covers 4 hours of local
/// wall-clock time (slot 0 = 00:00–04:00, slot 5 = 20:00–24:00).
public struct HeatmapBucket: Hashable {
    public let dayIndex: Int
    public let slotIndex: Int

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
    /// Uses `Calendar.current` so day/slot boundaries reflect the
    /// user's local timezone, which is the desired behavior.
    public static func bucketize(
        _ snapshots: [UsageSnapshot],
        now: Date
    ) -> [HeatmapBucket: Double] {
        var maxFraction: [HeatmapBucket: Double] = [:]
        let cal = Calendar.current
        let todayMidnight = cal.startOfDay(for: now)

        for s in snapshots {
            let snapMidnight = cal.startOfDay(for: s.timestamp)
            let dayDelta = cal.dateComponents([.day],
                                              from: snapMidnight,
                                              to: todayMidnight).day ?? 0
            let dayIndex = 27 - dayDelta
            guard (0...27).contains(dayIndex) else { continue }

            let hour = cal.component(.hour, from: s.timestamp)
            let key = HeatmapBucket(dayIndex: dayIndex, slotIndex: hour / 4)
            maxFraction[key] = max(maxFraction[key] ?? 0, s.fraction5h)
        }
        return maxFraction
    }
}
```

- [ ] **Step 4: Run tests, confirm all 5 pass**

```bash
cd Packages/UsageCore && swift test --filter HeatmapBucketingTests 2>&1 | tail -10
```

Expected: PASS — `Test Suite 'HeatmapBucketingTests' passed`, 5 tests executed.

- [ ] **Step 5: Commit**

```bash
git add Packages/UsageCore/Sources/UsageCore/Heatmap/HeatmapBucket.swift \
        Packages/UsageCore/Tests/UsageCoreTests/Heatmap/HeatmapBucketingTests.swift
git commit -m "$(cat <<'EOF'
feat(core): add HeatmapBucket + bucketize for 1m heatmap

Pure data layer for the upcoming 1-month heatmap visualization.
Lives in UsageCore so it's reachable from UsageCoreTests; the Mac
app's HeatmapView will consume it.

bucketize takes the most recent 28 days of snapshots and produces
a [HeatmapBucket: Double] keyed by (dayIndex 0..27, slotIndex 0..5).
Cell value = max(fraction5h) within the 4-hour bucket — peaks
read more honestly than averages, which would be biased toward
"fullness near reset" on a cumulative-counter window.

Calendar.current means slot boundaries follow the user's local
timezone — desirable for "my morning / afternoon / evening" UX.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Rename `ChartView.swift` → `LineChartView.swift`

**Files:**
- Rename: `Apps/ClaudeWatchMac/Popover/ChartView.swift` → `Apps/ClaudeWatchMac/Popover/LineChartView.swift`
- Modify: `Apps/ClaudeWatchMac/Popover/PopoverRootView.swift` (caller update)

- [ ] **Step 1: Rename the file via git**

```bash
git mv Apps/ClaudeWatchMac/Popover/ChartView.swift \
       Apps/ClaudeWatchMac/Popover/LineChartView.swift
```

- [ ] **Step 2: Rename the struct inside the file**

In `Apps/ClaudeWatchMac/Popover/LineChartView.swift`, replace:

```swift
struct ChartView: View {
```

with:

```swift
struct LineChartView: View {
```

- [ ] **Step 3: Update the caller in PopoverRootView**

In `Apps/ClaudeWatchMac/Popover/PopoverRootView.swift`, find:

```swift
            ChartView(snapshots: snapshots,
                      forecast: controller.state.forecast,
                      timeframe: timeframe,
                      nextReset5h: controller.state.latest?.resetTime5h,
                      nextResetWeek: controller.state.latest?.resetTimeWeek)
```

Replace with:

```swift
            LineChartView(snapshots: snapshots,
                          forecast: controller.state.forecast,
                          timeframe: timeframe,
                          nextReset5h: controller.state.latest?.resetTime5h,
                          nextResetWeek: controller.state.latest?.resetTimeWeek)
```

- [ ] **Step 4: Regenerate xcodeproj and build**

```bash
xcodegen generate 2>&1 | tail -2
xcodebuild -project ClaudeWatch.xcodeproj \
  -scheme ClaudeWatchMac \
  -configuration Debug \
  -destination 'platform=macOS' \
  build 2>&1 | grep -E "(error:|\*\* )" | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Apps/ClaudeWatchMac/Popover/LineChartView.swift \
        Apps/ClaudeWatchMac/Popover/PopoverRootView.swift
git commit -m "$(cat <<'EOF'
refactor(mac): rename ChartView -> LineChartView

About to add HeatmapView as a sibling for the upcoming 1m
timeframe. Renaming "the chart" -> "the line chart" makes that
distinction explicit at the file/struct level.

Pure rename — no behavior change.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Add `Timeframe.oneMonth`, remove `.oneHour`

**Files:**
- Modify: `Apps/ClaudeWatchMac/Popover/TimeframePicker.swift` (enum changes)
- Modify: `Apps/ClaudeWatchMac/Popover/LineChartView.swift` (axisFormat case)
- Modify: `Apps/ClaudeWatchMac/Popover/PopoverRootView.swift` (default state)

- [ ] **Step 1: Update the Timeframe enum**

In `Apps/ClaudeWatchMac/Popover/TimeframePicker.swift`, replace the entire enum body:

```swift
enum Timeframe: String, CaseIterable, Identifiable {
    case oneHour = "1h"
    case eightHour = "8h"
    case dayHour = "24h"
    case oneWeek = "1w"
    var id: String { rawValue }
    var seconds: TimeInterval {
        switch self {
        case .oneHour: return 3600
        case .eightHour: return 8 * 3600
        case .dayHour: return 24 * 3600
        case .oneWeek: return 7 * 24 * 3600
        }
    }
}
```

with:

```swift
enum Timeframe: String, CaseIterable, Identifiable {
    case eightHour = "8h"
    case dayHour = "24h"
    case oneWeek = "1w"
    case oneMonth = "1m"
    var id: String { rawValue }
    var seconds: TimeInterval {
        switch self {
        case .eightHour: return 8 * 3600
        case .dayHour: return 24 * 3600
        case .oneWeek: return 7 * 24 * 3600
        case .oneMonth: return 28 * 24 * 3600
        }
    }
}
```

- [ ] **Step 2: Update axisFormat in LineChartView to remove `.oneHour` and add `.oneMonth`**

In `Apps/ClaudeWatchMac/Popover/LineChartView.swift`, find:

```swift
    private var axisFormat: Date.FormatStyle {
        switch timeframe {
        case .oneHour, .eightHour:
            return .dateTime.hour().minute()
        case .dayHour:
            return .dateTime.hour()
        case .oneWeek:
            return .dateTime.month(.abbreviated).day()
        }
    }
```

Replace with:

```swift
    private var axisFormat: Date.FormatStyle {
        switch timeframe {
        case .eightHour:
            return .dateTime.hour().minute()
        case .dayHour:
            return .dateTime.hour()
        case .oneWeek, .oneMonth:
            // .oneMonth is here defensively — LineChartView never
            // actually renders for the month view (HeatmapView does).
            // Keeping the case exhaustive avoids a compile-time
            // hole if the dispatch ever changes.
            return .dateTime.month(.abbreviated).day()
        }
    }
```

- [ ] **Step 3: Update default state in PopoverRootView**

In `Apps/ClaudeWatchMac/Popover/PopoverRootView.swift`, find:

```swift
    @State private var timeframe: Timeframe = .oneHour
```

Replace with:

```swift
    @State private var timeframe: Timeframe = .eightHour
```

- [ ] **Step 4: Build to verify all references are consistent**

```bash
xcodebuild -project ClaudeWatch.xcodeproj \
  -scheme ClaudeWatchMac \
  -configuration Debug \
  -destination 'platform=macOS' \
  build 2>&1 | grep -E "(error:|\*\* )" | tail -5
```

Expected: `** BUILD SUCCEEDED **`. If you see `'oneHour' has been renamed` or `cannot find 'oneHour'`, run `grep -rn "oneHour" Apps/ClaudeWatchMac` and fix the holdouts.

- [ ] **Step 5: Commit**

```bash
git add Apps/ClaudeWatchMac/Popover/TimeframePicker.swift \
        Apps/ClaudeWatchMac/Popover/LineChartView.swift \
        Apps/ClaudeWatchMac/Popover/PopoverRootView.swift
git commit -m "$(cat <<'EOF'
feat(mac): replace 1h timeframe with 1m

Drops the 1-hour chart timeframe (too short to be informative for
a usage tracker — 90s polling barely fills it) and adds a
1-month case in its place. The new picker order is 8h / 24h / 1w / 1m.

Default popover-open timeframe shifts from .oneHour to .eightHour.

LineChartView's axisFormat keeps a .oneMonth case for exhaustiveness,
even though the dispatch in the next commit will route .oneMonth
to HeatmapView instead of LineChartView.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Create `HeatmapPalette.swift`

**Files:**
- Create: `Apps/ClaudeWatchMac/Popover/HeatmapPalette.swift`

- [ ] **Step 1: Create the palette file**

Create `Apps/ClaudeWatchMac/Popover/HeatmapPalette.swift`:

```swift
import SwiftUI

/// Color scale for the 1-month heatmap cells. Single source of truth
/// so HeatmapView and any future overlay/legend stay visually
/// consistent.
///
/// Encoding rationale:
///   • Green base — heatmap intensity uses the same 5h-line color
///     family from ChartPalette, so the heatmap reads as part of
///     the same visualization story.
///   • Linear opacity ramp from 0.05 (visible-but-faint) to 0.85
///     (saturated). Pure 0% becomes a near-empty cell rather than a
///     fully transparent one — the user still sees "we have data
///     here, it was just empty" instead of "no data at all".
///   • ≥ 90% jumps to orange, matching the warning color GaugeCardView
///     uses for ≥ 75% on the 5h gauge. Visual continuity is intentional
///     — the user's "danger" reading should be the same across views.
///   • nil (no data) returns a faint gray border tone, distinguishing
///     "unpolled" from "polled but idle".
enum HeatmapPalette {
    static func cellColor(_ fraction: Double?) -> Color {
        guard let f = fraction else { return Color.gray.opacity(0.15) }
        if f >= 0.9 { return Color.orange.opacity(0.85) }
        return Color.green.opacity(0.05 + min(f, 0.9) * 0.85)
    }
}
```

- [ ] **Step 2: Build to verify the file compiles in isolation**

```bash
xcodegen generate 2>&1 | tail -2
xcodebuild -project ClaudeWatch.xcodeproj \
  -scheme ClaudeWatchMac \
  -configuration Debug \
  -destination 'platform=macOS' \
  build 2>&1 | grep -E "(error:|\*\* )" | tail -5
```

Expected: `** BUILD SUCCEEDED **`. (The palette is unused at this point but should compile.)

- [ ] **Step 3: Commit**

```bash
git add Apps/ClaudeWatchMac/Popover/HeatmapPalette.swift
git commit -m "$(cat <<'EOF'
feat(mac): add HeatmapPalette color scale

Centralizes the cell-color function for the upcoming HeatmapView.
Linear green opacity ramp 0.05–0.85 for normal cells; jumps to
orange at ≥ 90% so the danger threshold matches GaugeCardView's
existing warning color. nil (no data) returns a faint gray border
tone — distinguishes "unpolled" from "polled but idle".

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Create `HeatmapView.swift` (Canvas-based renderer)

**Files:**
- Create: `Apps/ClaudeWatchMac/Popover/HeatmapView.swift`

- [ ] **Step 1: Create the heatmap view**

Create `Apps/ClaudeWatchMac/Popover/HeatmapView.swift`:

```swift
import SwiftUI
import UsageCore

/// 6 × 28 cell heatmap covering the most recent 28 days. Each row
/// is a 4-hour slot of local-time-of-day (00–04 … 20–24); each
/// column is one day, with today on the right.
///
/// Cell color encodes max(fraction5h) within that bucket — see
/// docs/superpowers/specs/2026-05-06-onemonth-heatmap-design.md.
///
/// Drawn with SwiftUI Canvas instead of Charts.RectangleMark for:
///   • pixel-precise cell sizing (10.2 × 16 pt with 1 pt gaps)
///   • single-pass GraphicsContext fill instead of 168 view nodes
///   • room to add custom hover/tap tooltips later without fighting
///     Charts' chartProxy layer
struct HeatmapView: View {
    let snapshots: [UsageSnapshot]

    /// Number of days the heatmap covers, fixed at 28.
    private let days = 28
    /// Number of 4-hour slots per day, fixed at 6.
    private let slots = 6
    /// Reserved width on the left of the canvas for hour-of-day
    /// labels (00, 04, 08, 12, 16, 20).
    private let leftAxisWidth: CGFloat = 24
    /// Reserved height at the top for sparse date labels.
    private let topLabelHeight: CGFloat = 14

    var body: some View {
        Canvas { ctx, size in
            let buckets = HeatmapBucket.bucketize(snapshots, now: Date())

            let gridOriginX = leftAxisWidth
            let gridOriginY = topLabelHeight + 2
            let gridWidth   = size.width  - leftAxisWidth
            let gridHeight  = size.height - topLabelHeight - 2

            let cellW = gridWidth  / CGFloat(days)
            let cellH = gridHeight / CGFloat(slots)
            let gap: CGFloat = 1

            // 1. Cell rectangles.
            for day in 0..<days {
                for slot in 0..<slots {
                    let key = HeatmapBucket(dayIndex: day, slotIndex: slot)
                    let value = buckets[key]
                    let color = HeatmapPalette.cellColor(value)
                    let rect = CGRect(
                        x: gridOriginX + CGFloat(day) * cellW + gap / 2,
                        y: gridOriginY + CGFloat(slot) * cellH + gap / 2,
                        width:  cellW - gap,
                        height: cellH - gap)
                    ctx.fill(Path(rect), with: .color(color))
                }
            }

            // 2. Left-axis hour labels (00, 04, 08, 12, 16, 20).
            for slot in 0..<slots {
                let label = String(format: "%02d", slot * 4)
                let text = Text(label)
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                let resolved = ctx.resolve(text)
                let textSize = resolved.measure(in: CGSize(width: leftAxisWidth,
                                                           height: cellH))
                let textOrigin = CGPoint(
                    x: leftAxisWidth - textSize.width - 2,
                    y: gridOriginY + CGFloat(slot) * cellH + (cellH - textSize.height) / 2)
                ctx.draw(resolved, at: textOrigin, anchor: .topLeading)
            }

            // 3. Sparse top-axis date labels — every 7th day.
            let cal = Calendar.current
            for day in stride(from: 0, to: days, by: 7) {
                let dayOffset = -(days - 1 - day)
                guard let date = cal.date(byAdding: .day, value: dayOffset, to: Date()) else { continue }
                let f = DateFormatter()
                f.dateFormat = "M/d"
                let text = Text(f.string(from: date))
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                let resolved = ctx.resolve(text)
                let textSize = resolved.measure(in: CGSize(width: cellW * 7,
                                                           height: topLabelHeight))
                let textOrigin = CGPoint(
                    x: gridOriginX + CGFloat(day) * cellW,
                    y: 0)
                ctx.draw(resolved, at: textOrigin, anchor: .topLeading)
            }
        }
        .frame(height: 140)
    }
}
```

- [ ] **Step 2: Build to verify the file compiles**

```bash
xcodegen generate 2>&1 | tail -2
xcodebuild -project ClaudeWatch.xcodeproj \
  -scheme ClaudeWatchMac \
  -configuration Debug \
  -destination 'platform=macOS' \
  build 2>&1 | grep -E "(error:|\*\* )" | tail -5
```

Expected: `** BUILD SUCCEEDED **`. (HeatmapView isn't wired up yet — the next task does that.)

- [ ] **Step 3: Commit**

```bash
git add Apps/ClaudeWatchMac/Popover/HeatmapView.swift
git commit -m "$(cat <<'EOF'
feat(mac): add HeatmapView (Canvas renderer for 1m timeframe)

Renders a 6×28 cell grid (4-hour slots × 28 days) using SwiftUI
Canvas. Pulls bucketed values from UsageCore.HeatmapBucket and
colors each cell via HeatmapPalette.

Two axis label sets are drawn inline:
  • Left: hour labels 00 / 04 / 08 / 12 / 16 / 20
  • Top:  sparse date labels every 7 days (4 labels total)

Not wired into PopoverRootView yet — the next commit dispatches
between LineChartView and HeatmapView based on the selected
timeframe.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Wire `HeatmapView` into `PopoverRootView`, bump heights

**Files:**
- Modify: `Apps/ClaudeWatchMac/Popover/PopoverRootView.swift` (dispatch + chart frame)
- Modify: `Apps/ClaudeWatchMac/Popover/LineChartView.swift` (chart frame 90 → 140)
- Modify: `Apps/ClaudeWatchMac/Popover/PopoverController.swift` (popover content size)

- [ ] **Step 1: Update LineChartView's frame height from 90 to 140**

In `Apps/ClaudeWatchMac/Popover/LineChartView.swift`, find:

```swift
        .frame(height: 90)
    }
```

Replace with:

```swift
        .frame(height: 140)
    }
```

- [ ] **Step 2: Update PopoverRootView to dispatch on timeframe**

In `Apps/ClaudeWatchMac/Popover/PopoverRootView.swift`, find:

```swift
            TimeframePicker(selection: $timeframe)
            LineChartView(snapshots: snapshots,
                          forecast: controller.state.forecast,
                          timeframe: timeframe,
                          nextReset5h: controller.state.latest?.resetTime5h,
                          nextResetWeek: controller.state.latest?.resetTimeWeek)
```

Replace with:

```swift
            TimeframePicker(selection: $timeframe)
            // 1m switches to a heatmap visualization. Other timeframes
            // continue to use the line chart with reset markers and
            // forecast overlay.
            if timeframe == .oneMonth {
                HeatmapView(snapshots: snapshots)
            } else {
                LineChartView(snapshots: snapshots,
                              forecast: controller.state.forecast,
                              timeframe: timeframe,
                              nextReset5h: controller.state.latest?.resetTime5h,
                              nextResetWeek: controller.state.latest?.resetTimeWeek)
            }
```

- [ ] **Step 3: Update PopoverController's contentSize for the 50pt growth**

In `Apps/ClaudeWatchMac/Popover/PopoverController.swift`, find:

```swift
        popover.contentSize = NSSize(width: 340, height: 420)
```

Replace with:

```swift
        // Height grew 50 pt vs v0.1.8: chart frame went from 90 to
        // 140 pt to give the 1m heatmap room for ~16 pt × 6-row
        // cells. Other tabs share the same height so switching
        // tabs doesn't animate the popover's outer frame.
        popover.contentSize = NSSize(width: 340, height: 470)
```

- [ ] **Step 4: Build + visually verify**

```bash
xcodebuild -project ClaudeWatch.xcodeproj \
  -scheme ClaudeWatchMac \
  -configuration Debug \
  -destination 'platform=macOS' \
  build 2>&1 | grep -E "(error:|\*\* )" | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

Then run the app from Xcode (Cmd-R) and:

1. Click the menu bar icon to open the popover.
2. Confirm the picker shows `8h / 24h / 1w / 1m` (no 1h).
3. Confirm the default tab on open is `8h` and the line chart renders.
4. Click `1m`. Heatmap appears with ~168 cells. Today's column is rightmost.
5. Click back to `8h` / `24h` / `1w` — line chart reappears at the same vertical extent (no popover height jump).

If the heatmap looks empty (all faint gray), the database may have no data yet — leave the app running for a few minutes and click `1m` again. If today's column has cells but older days are empty, that's expected for a fresh installation.

- [ ] **Step 5: Commit**

```bash
git add Apps/ClaudeWatchMac/Popover/PopoverRootView.swift \
        Apps/ClaudeWatchMac/Popover/LineChartView.swift \
        Apps/ClaudeWatchMac/Popover/PopoverController.swift
git commit -m "$(cat <<'EOF'
feat(mac): dispatch 1m timeframe to HeatmapView

PopoverRootView now switches between HeatmapView and LineChartView
based on the selected timeframe. The chart frame grew from 90 pt
to 140 pt across all four tabs; popover contentSize grew from
(340, 420) to (340, 470) to absorb the 50 pt difference.

Holding chart height constant across timeframes (rather than
animating per-tab) avoids a jarring outer-frame jump when the
user switches between line chart and heatmap views.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Self-review

**Spec coverage:**

| Spec section | Implemented in task |
|---|---|
| Remove `.oneHour`, add `.oneMonth` | Task 3 |
| Default timeframe `.oneHour` → `.eightHour` | Task 3 |
| Picker label order `8h / 24h / 1w / 1m` | Task 3 (CaseIterable order) |
| 6 × 28 grid, today on right | Task 5 (HeatmapView body) |
| `max(fraction5h)` per cell | Task 1 (HeatmapBucket.bucketize) |
| Color: green ramp + orange ≥ 90% + gray no-data | Task 4 (HeatmapPalette) |
| Canvas (not Charts.RectangleMark) | Task 5 |
| Chart frame 90 → 140 pt for all tabs | Task 6 (LineChartView + dispatch keep same height) |
| Popover contentSize 420 → 470 | Task 6 |
| Local-timezone bucketing | Task 1 (Calendar.current) |
| Slot intervals `[start, end)` | Task 1 (`hour / 4`) |
| 5 unit tests (empty, single, max-not-avg, 28-day cutoff, midnight) | Task 1 |
| `ChartView.swift` rename to `LineChartView.swift` | Task 2 |
| Bucketing lives in `UsageCore` (testable) | Task 1 (deviation from spec — documented in plan header) |

No gaps.

**Placeholder scan:** No TBD/TODO/"add error handling"/"similar to" strings. Each step has runnable code or commands.

**Type consistency:**

| Type / function | Defined | Used |
|---|---|---|
| `HeatmapBucket` (struct) | Task 1 | Task 5 |
| `HeatmapBucket.bucketize(_:now:)` | Task 1 | Task 5 |
| `HeatmapPalette.cellColor(_:)` | Task 4 | Task 5 |
| `HeatmapView(snapshots:)` | Task 5 | Task 6 |
| `LineChartView(...)` | Task 2 (renamed) | Task 6 |
| `Timeframe.oneMonth` | Task 3 | Task 6 |

All names match across tasks.
