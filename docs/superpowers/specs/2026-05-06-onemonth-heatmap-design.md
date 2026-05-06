# 1-Month Heatmap & Timeframe Cleanup — Design

**Date:** 2026-05-06
**Status:** Approved
**Target release:** v0.1.9 (after v0.1.8 ships through App Store review)

---

## Goal

Replace the 1-hour timeframe — which is too short to be informative for a usage-tracker — with a **1-month heatmap** that surfaces monthly activity patterns at a glance. The 8h / 24h / 1w line-chart timeframes stay unchanged.

Reading the heatmap, the user should be able to answer in two seconds:

- _"Which days during the past 4 weeks did I come close to the 5h limit?"_
- _"What time of day am I typically heaviest?"_

---

## Scope

### In scope

- Remove `Timeframe.oneHour` from the segmented picker.
- Add `Timeframe.oneMonth` (label `1m`).
- Render the 1m view as a 6 × 28 cell heatmap (6 four-hour slots × 28 days).
- Heatmap uses `max(fraction5h)` per bucket as its cell color.
- Increase chart frame height from 90 pt to **140 pt for all tabs** (avoids per-tab layout jumping).
- Pull the heatmap into its own SwiftUI view; split the existing `ChartView` body into a sibling `LineChartView`.

### Out of scope

- Hover/tap tooltip showing exact bucket values (defer to a later release).
- Configurable bucket size (always 4 h).
- 1-month forecast (the existing `LinearForecaster` is short-term; long-horizon forecasting is a separate problem).
- 7-day / weekly aggregate overlay on the heatmap.
- Backfilling historical data — only existing local snapshots are visualized.

---

## UI changes

### Timeframe picker (top of chart area)

```
Before:  [1h] [8h] [24h] [1w]
After:   [8h] [24h] [1w] [1m]
```

The default selected timeframe on popover open changes from `.oneHour` → `.eightHour`.

### Chart area — physical layout

```
Total content width:   316 pt   (340 pt popover − 12 pt × 2 padding)
Chart frame height:    140 pt   (was 90 pt; increased uniformly across tabs)
```

For the line-chart tabs (8h / 24h / 1w), the visual is the same as today, just with 50 pt of extra vertical room. No code change to the line-drawing logic — only `.frame(height: 140)` instead of 90.

For the 1m tab, the area is filled by `HeatmapView` instead of the line chart.

### Popover total height

The popover's `contentSize` is set to `(340, 420)` in `PopoverController.swift` today. With the 50 pt chart growth, this becomes `(340, 470)`. The popover height stays constant across all four tabs — no animation when switching, just one fixed canvas where the inner chart area renders different content.

### 1m heatmap layout

```
                   ←─────── 28 days, oldest → today ───────→
            ┌──┬──┬──┬──┬──┬──┬──┬──── ... ────┬──┐
   00–04   │  │  │  │  │  │  │  │              │  │
   04–08   │  │  │  │  │  │  │  │              │  │
   08–12   │  │  │  │  │  │  │  │              │  │
   12–16   │  │  │  │  │  │  │  │              │  │
   16–20   │  │  │  │  │  │  │  │              │  │
   20–24   │  │  │  │  │  │  │  │              │  │
            └──┴──┴──┴──┴──┴──┴──┴──── ... ────┴──┘
             |                                     |
             5/9 (28 d ago)                        6/6 (today)
```

- 6 rows = four-hour time-of-day slots (`00–04`, `04–08`, `08–12`, `12–16`, `16–20`, `20–24`).
- 28 columns = the most recent 28 days, today on the right.
- Left axis labels: `0`, `4`, `8`, `12`, `16`, `20` (24 pt of width reserved).
- Bottom axis: 5 sparse date labels (every ~7 days), so the labels never collide.

### Cell sizing

```
Drawing region:    286 pt × 96 pt        (after 24 pt left axis + label padding)
Cell width:        286 / 28 = 10.2 pt
Cell height:       96 / 6   = 16 pt
Inter-cell gap:    1 pt
```

Cells are too narrow for in-cell text. Tooltips are deferred (see Out of scope).

---

## Data flow

### Source

`SnapshotRepository.fetchRecent(within: 28 * 86400)` returns up to ~26 880 snapshots (28 days × 24 h × 60 min × 60 s ÷ 90 s polling cadence).

### Time-of-day in user's local timezone

The bucketing uses `Calendar.current`, which reads the device's local timezone. `slotIndex = hour / 4` therefore reflects the user's wall-clock view of "my morning / afternoon / evening" — not UTC. A snapshot at `2026-05-06 14:23` in San Francisco lands in slot 3 (12–16) for the user; the same `Date` would have a different slot for someone in Tokyo. This is the desired behavior for a personal usage tracker.

Cross-timezone travel during the 28-day window can cause bucket boundaries to shift mid-data. We accept this for MVP — the heatmap will still be readable, just with mildly skewed columns at the travel transition. Real fix would require remembering the timezone at each snapshot, which would be a snapshot-schema change.

Slot intervals are inclusive of their start, exclusive of their end: slot 1 (`04–08`) covers `[04:00:00, 08:00:00)`. A snapshot at exactly `08:00:00.001` belongs to slot 2.

### Bucketing

```swift
struct HeatmapBucket: Hashable {
    let dayIndex: Int    // 0 = 28 days ago, 27 = today
    let slotIndex: Int   // 0..5, derived as Calendar.hour(of: timestamp) / 4
}

func bucketize(_ snapshots: [UsageSnapshot], now: Date) -> [HeatmapBucket: Double] {
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
```

### Cell metric

`max(fraction5h)` within each bucket — "how close did I get to the 5 h ceiling during this 4-hour slot?"

We chose `max` over `avg` deliberately:

- **`max`** gives the visual peak; the heatmap reads as "intensity" (heavy slots stand out).
- **`avg`** would be biased toward "fullness near reset" (since `used_5h` is cumulative), which is misleading — a user who used heavily early then idled would still show a bright cell because the 5h window stayed full.

---

## Visual design

### Color palette

The heatmap reuses the existing project palette so it reads as part of the same visualization family:

| State | Color | Notes |
|---|---|---|
| No data | `Color.gray.opacity(0.15)` (border only) | Distinguishes "we polled but it was empty" from "no poll happened" |
| Idle (0%) | `Color.green.opacity(0.05)` | Almost transparent — reads as "empty cell" |
| Mid (50%) | `Color.green.opacity(0.475)` | Linear ramp |
| Heavy (80%) | `Color.green.opacity(0.85)` | Saturated green, attention-getting |
| **Danger (≥ 90%)** | `Color.orange.opacity(0.85)` | Same orange that `GaugeCardView` uses for ≥ 75% — visual continuity |

```swift
enum HeatmapPalette {
    static func cellColor(_ fraction: Double?) -> Color {
        guard let f = fraction else { return Color.gray.opacity(0.15) }
        if f >= 0.9 { return Color.orange.opacity(0.85) }
        return Color.green.opacity(0.05 + min(f, 0.9) * 0.85)
    }
}
```

### Why `Canvas` instead of SwiftUI Charts `RectangleMark`

- `Charts` is built around line/bar/area marks; cell-grid layouts work but require layering `RectangleMark` with custom `chartXScale` / `chartYScale` and fighting the auto-layout.
- 168 cells with custom `Color.opacity` per cell render measurably faster in `Canvas` (single `GraphicsContext.fill` per cell).
- `Canvas` will make hover/tooltip integration easier in a future release.

---

## File structure

| File | Change | Responsibility |
|---|---|---|
| `Apps/ClaudeWatchMac/Popover/TimeframePicker.swift` | Modify | Remove `.oneHour`, add `.oneMonth`. Update `seconds` accessor. |
| `Apps/ClaudeWatchMac/Popover/ChartView.swift` | Rename + slim | Becomes `LineChartView.swift`. Body unchanged except removing the `.oneHour` case in `axisFormat`. |
| `Apps/ClaudeWatchMac/Popover/HeatmapView.swift` | New | The Canvas-based heatmap renderer + bucketing function. |
| `Apps/ClaudeWatchMac/Popover/HeatmapPalette.swift` | New | Color scale (`cellColor(_ fraction:)`). |
| `Apps/ClaudeWatchMac/Popover/PopoverRootView.swift` | Modify | Switch on `timeframe == .oneMonth` to choose `HeatmapView` vs `LineChartView`. Default `@State timeframe = .eightHour`. Pass 28-day snapshot window to `HeatmapView`. |
| `Apps/ClaudeWatchMac/Resources/*/Localizable.strings` × 8 | Modify | Add `timeframe.1m` label translations. (1h is just a literal `"1h"` raw value, no localization needed.) |

`ChartView.swift` is kept as a file path for git diff continuity but renamed via `git mv` to `LineChartView.swift`. The forecast logic and reset-line logic stay in this file untouched.

---

## Migration: removing `.oneHour`

`Timeframe.oneHour` is referenced in three places (verified via grep):

1. **`TimeframePicker.swift`** — declaration (delete).
2. **`ChartView.swift` `axisFormat`** — `case .oneHour, .eightHour` becomes just `case .eightHour`.
3. **`PopoverRootView.swift`** — `@State private var timeframe: Timeframe = .oneHour` becomes `.eightHour`.

No persisted state references `.oneHour` (the popover always opens with the default; the user's last choice isn't remembered). No external references in `UsageCore`.

If a user is on v0.1.8 with the popover open at "1h" and updates to v0.1.9, the next popover open shows "8h" — there's no migration path needed.

---

## Localization

### New string

| Key | en | zh-Hans |
|---|---|---|
| `timeframe.1m` | `1m` | `1月` |

(Other 6 locales: `1m` works as a universal abbreviation; we use the same token across all 8.)

The existing button labels (`8h`, `24h`, `1w`) are also displayed verbatim today — they're not localized strings, just the enum's `rawValue`. We keep that approach for `1m`.

### Removed strings

None. The `1h` button label was also a literal, not a localized string.

---

## Testing

### Unit tests (in `UsageCoreTests`)

These tests live next to existing `LinearForecasterTests` and use the same fixture-based pattern:

1. **`HeatmapBucketing_emptySnapshots_returnsEmptyMap`** — no input → empty `[HeatmapBucket: Double]`.
2. **`HeatmapBucketing_singleSnapshot_inCorrectBucket`** — one snapshot at `2026-05-06 14:23` should land in `(dayIndex: 27, slotIndex: 3)` (12–16 slot of today).
3. **`HeatmapBucketing_takesMaxNotAverage`** — three snapshots in the same slot at 30%, 60%, 45% → bucket value = 0.60.
4. **`HeatmapBucketing_dropsSnapshotsOlderThan28Days`** — snapshot at -29 days is excluded; one at -27 days is included.
5. **`HeatmapBucketing_dayBoundaryAtMidnight`** — snapshot at `2026-05-06 23:59:59` → `(27, 5)`; snapshot 2 seconds later at `2026-05-07 00:00:01` → would be next day, out of range.

### Visual sanity (manual)

Build app, switch to 1m tab, verify:

- All 168 cells render.
- Today's column is rightmost.
- A mostly-idle period shows pale-green / empty cells.
- Heavy hours show saturated green or orange.
- Switching back to 8h / 24h / 1w shows the line chart at 140 pt height with the same data the user expects.

---

## Rollout

This change goes into **v0.1.9** alongside the recovery-banner work already done in this branch:

- Lands after Apple approves v0.1.8 from the App Store review queue.
- Bumps `MARKETING_VERSION` to `0.1.9` and `CFBundleVersion` to `11`.
- Both DMG and Mac App Store builds get the change in lockstep.
- The chart-area visual is the most user-visible change in v0.1.9 and should anchor the release notes.
