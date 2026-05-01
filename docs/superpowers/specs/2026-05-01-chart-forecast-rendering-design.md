# Chart Forecast Rendering — Design Spec

**Date:** 2026-05-01
**Status:** Approved (brainstorming complete; pre-implementation)
**Scope:** macOS app popover chart only (`Apps/ClaudeWatchMac/Popover/`)
**Parent spec:** `2026-04-30-claude-usage-tracker-design.md` (§ 5 Forecast math, § 6 macOS UI)

## Problem

Two visible bugs in the popover chart:

1. **Color collapse.** The actual-usage `LineMark` (green) and the forecast `LineMark` (intended orange dashed) merged into a single visual line, both rendered solid green. Cause: Swift Charts groups all `LineMark`s without a `series:` differentiator into one series, and per-`LineMark` `.foregroundStyle()` modifiers don't fully override the merged-series style.

2. **Misleading forecast/caption pairing.** When `LinearForecaster.projectedHitTime` is `nil` (i.e. the user won't hit the limit before the next 5h reset), the caption reads `⏱ stable, no projection` while the chart still draws a sloped line. The line says "going up" but the caption says "stable" — contradiction.

## Goals

- Forecast line renders as visually distinct from actual usage on every appearance.
- The line's color encodes its actionability so the user can tell "this matters" from "this is just there for completeness."
- Caption text matches the chart state — never contradicts it.
- No changes to `UsageCore` logic. All work is in two view files.

## Non-goals

- Changes to forecast math (slope, R², hit-time computation) — out of scope.
- Changes to chart x-axis range, gauge cards, footer, reset markers, or the timeframe picker.
- Custom dash patterns per state. All dashed forecast lines use the same `[3, 2]` pattern; only color and opacity vary.
- Animations or transitions between states.

## Visual state matrix

The forecast can be in exactly one of five states. Each state pairs a chart line treatment with a caption:

| Forecast state | Detection | Forecast line on chart | Caption (`ForecastCaptionView`) |
|---|---|---|---|
| No forecast | `controller.state.forecast == nil` | hidden | `⏱ Building forecast…` (tertiary gray) |
| Stable | `forecast != nil && projectedHitTime == nil && slope <= 0.0001` | **gray dashed**, near-flat | `⏱ stable` |
| Trending up but won't hit | `forecast != nil && projectedHitTime == nil && slope > 0.0001` | **gray dashed**, sloped | `⏱ won't hit limit this window` |
| Hit projected, low confidence | `projectedHitTime != nil && rSquared < 0.5` | **light orange dashed**, sloped to 100% | `⏱ ~HH:MM (low confidence)` |
| Hit projected, high confidence | `projectedHitTime != nil && rSquared >= 0.5` | **orange dashed**, sloped to 100% | `⏱ likely full at HH:MM` |

Color hierarchy semantic: **gray = informational** (no action needed), **light orange = warning, low trust** (might hit limit, but the data is noisy), **orange = warning, trust** (clearly heading to the limit).

## Implementation

### Color values

```swift
// In ChartView.swift, computed per render based on forecast state.
private enum ForecastTone {
    case gray        // not actionable — slope ≤ 0.0001 or no projected hit
    case lightOrange // hit projected but R² < 0.5 (low confidence)
    case orange      // hit projected with R² >= 0.5

    var color: Color {
        switch self {
        case .gray:        return Color.gray.opacity(0.55)
        case .lightOrange: return Color.orange.opacity(0.45)
        case .orange:      return Color.orange
        }
    }
}
```

`gray` is a separate hue from `Color.indigo` (the 5h-reset marker) so they don't visually conflict. `Color.orange.opacity(0.45)` gives a clearly muted orange that reads as "less alarming" without becoming yellow.

### `LineMark` series fix

Both `LineMark`s gain a `series:` parameter so Swift Charts treats them independently:

```swift
// Actual usage (green, solid)
LineMark(
    x: .value("t", s.timestamp),
    y: .value("pct", s.fraction5h * 100),
    series: .value("kind", "actual"))
.foregroundStyle(.green)

// Forecast (color depends on state, dashed)
LineMark(
    x: .value("t", p.time),
    y: .value("pct", p.projectedFraction * 100),
    series: .value("kind", "forecast"))
.foregroundStyle(forecastTone.color)
.lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
```

The `series:` parameter is the canonical Swift Charts way to keep two same-y-axis lines separate. After this change, per-line modifiers are honored.

### Forecast tone selection

```swift
private func forecastTone(_ f: ForecastResult) -> ForecastTone {
    if f.projectedHitTime != nil {
        return f.isLowConfidence ? .lightOrange : .orange
    }
    return .gray
}
```

`isLowConfidence` already exists on `ForecastResult` (`rSquared < 0.5`).

### Caption logic

```swift
struct ForecastCaptionView: View {
    let forecast: ForecastResult?

    var body: some View {
        Text(captionText)
            .font(.system(size: 11))
            .foregroundStyle(captionStyle)
    }

    private var captionText: String {
        guard let f = forecast else { return "⏱ Building forecast…" }
        if let hit = f.projectedHitTime {
            let df = DateFormatter()
            df.timeStyle = .short
            let timeStr = df.string(from: hit)
            return f.isLowConfidence
                ? "⏱ ~\(timeStr) (low confidence)"
                : "⏱ likely full at \(timeStr)"
        }
        // Hit-time is nil. Distinguish "stable" from "trending up but
        // won't reach limit before reset."
        return f.slope > 0.0001
            ? "⏱ won't hit limit this window"
            : "⏱ stable"
    }

    private var captionStyle: HierarchicalShapeStyle {
        forecast == nil ? .tertiary : .secondary
    }
}
```

## Files changed

| File | Change |
|---|---|
| `Apps/ClaudeWatchMac/Popover/ChartView.swift` | Add `ForecastTone` enum + `forecastTone()` helper. Add `series:` to both `LineMark`s. Replace fixed `.foregroundStyle(.orange)` on the forecast with `.foregroundStyle(forecastTone.color)`. |
| `Apps/ClaudeWatchMac/Popover/ForecastCaptionView.swift` | Replace existing two-branch caption logic with the four-state version above. Use `forecast.slope` to disambiguate "stable" vs "won't hit limit this window." |

No changes to:
- `UsageCore` package (uses existing `slope`, `rSquared`, `projectedHitTime`, `isLowConfidence` API)
- `PopoverRootView.swift` (still passes the same props to `ChartView` and `ForecastCaptionView`)
- Tests (no logic changes; presentation only)

## Risks

| Risk | Mitigation |
|---|---|
| Swift Charts may still merge `LineMark`s of different series in some macOS 13 versions | Verified `series:` works on macOS 13 SDK; if not, fallback is `RuleMark` for forecast (less smooth but always separate) |
| Color choices may be hard to distinguish for users with color-vision deficiency | `gray` is a different hue *and* lower contrast than orange; light vs. full orange differ in opacity (visible to most CVD types) |
| `slope > 0.0001` threshold may misclassify slow climbs as "stable" | The same threshold is used in `LinearForecaster` for hit-time clamping, so UI and math stay coherent |

## Success criteria

- Open the popover with a positive-slope forecast that *does* project a hit time → forecast renders as **orange dashed** (or **light orange dashed** if `R² < 0.5`).
- Open the popover with a positive-slope forecast that *doesn't* project a hit time → forecast renders as **gray dashed**, caption reads `⏱ won't hit limit this window`.
- Open the popover with a near-flat forecast → forecast renders as **gray dashed (near-horizontal)**, caption reads `⏱ stable`.
- Open the popover before three snapshots have accumulated → forecast hidden, caption reads `⏱ Building forecast…`.
- The forecast line is never the same color as the actual-usage green line.
