import SwiftUI
import Charts
import UsageCore

/// Editorial color palette for the chart. Each metric has a fixed identity
/// color across all timeframes:
///   • green = 5h-window utilization (the "default neutral" metric color
///             in macOS conventions; doesn't claim a warning slot the
///             way orange or red would)
///   • teal  = 7-day weekly utilization (cool, slow-cycle counterpart;
///             pairs with green inside a related green-blue hue family)
///
/// Forecast (5h-window-based) is always gray-dashed; confidence is
/// encoded by the dash gap rather than color, so a high-confidence
/// projection looks "near-solid" and a stable/non-actionable one looks
/// "barely-there dotted."
enum ChartPalette {
    static let actual5h = Color.green
    static let actualWeek = Color.teal
    static let forecast = Color.gray.opacity(0.7)
    static let resetBoundary = Color.indigo.opacity(0.6)
}

struct ChartView: View {
    let snapshots: [UsageSnapshot]
    let forecast: ForecastResult?
    let timeframe: Timeframe
    /// The next 5h-window reset time from the most recent snapshot. Used to
    /// stamp vertical guide lines on the chart so the user can see when
    /// each rolling 5h window ends, especially on 8h / 24h views that
    /// span multiple windows.
    let nextReset5h: Date?
    /// The next 7-day window reset time. Used as the single reset marker
    /// on the 1w view (where 5h boundaries would just be visual noise).
    let nextResetWeek: Date?

    var body: some View {
        let now = Date()
        let cutoff = now.addingTimeInterval(-timeframe.seconds)
        // 1w view shows BOTH lines (week primary, 5h supporting context).
        // Other timeframes show only the 5h line — plotting weekly
        // utilization across an hour would barely move.
        let showsWeekLine = (timeframe == .oneWeek)
        // Forecast is short-term and 5h-window-based — meaningful on 1h /
        // 8h / 24h. We don't have a separate "weekly forecast", so the 1w
        // view doesn't draw it.
        let showsForecast = !showsWeekLine

        // Compute the chart's right-edge timestamp. Two contributors:
        //
        //   1. Forecast cap — keeps the forecast line from blowing the
        //      chart out past its labeled timeframe (1/4 of timeframe).
        //   2. Reset marker visibility — the user wants to SEE the
        //      upcoming reset (5h or weekly) on every chart, even if
        //      it's beyond the forecast cap. Extend xMax to include
        //      it, but cap the extension at one full timeframe forward
        //      so the chart never grows more than ~2× the labeled span.
        //
        // ViewBuilder forbids mutable vars / non-view ifs at body's top
        // level, so we compute via an immediately-invoked closure.
        let xMax: Date = {
            let maxFutureForecast = timeframe.seconds * 0.25
            let forecastEnd = forecast?.line.last?.time ?? now
            let cappedForecastEnd = min(forecastEnd, now.addingTimeInterval(maxFutureForecast))
            var m = showsForecast ? max(now, cappedForecastEnd) : now

            let extensionCap = now.addingTimeInterval(timeframe.seconds)
            let upcomingReset: Date? = showsWeekLine ? nextResetWeek : nextReset5h
            if let r = upcomingReset, r > m {
                m = min(r, extensionCap)
            }
            return m
        }()
        let visible = snapshots.filter { $0.timestamp >= cutoff }
        let visibleForecast = forecast?.line.filter { $0.time <= xMax } ?? []

        // Reset markers:
        //   • 1h/8h/24h → indigo lines at every 5h boundary that falls
        //     inside the chart range, derived deterministically from
        //     the API's nextReset5h by stepping ±5h. No snapshot
        //     scanning, no drop-detection heuristics.
        //   • 1w → just the upcoming weekly reset (the saw-tooth pattern
        //     of the 5h line itself shows where rolling resets happened,
        //     so dotting the chart with ~33 markers is just noise).
        let resetMarks: [Date] = showsWeekLine
            ? weeklyResetMarks(in: cutoff...xMax)
            : fiveHourResetTimes(in: cutoff...xMax, snapshots: visible)
        // Augment the raw 5h snapshot stream with synthetic step-down
        // points at every reset time, so the line visibly drops to
        // 0% AT THE INDIGO BOUNDARY instead of slanting smoothly past
        // it. The drop happens at the exact API reset time — same x
        // as the RuleMark — so the green descent and indigo line
        // coincide perfectly.
        let line5h = augmented5hLine(visible, resets: resetMarks)

        Chart {
            // Data lines first, reset markers ON TOP — Swift Charts
            // paints in declaration order, so the indigo RuleMarks must
            // come AFTER the green LineMark. Otherwise a vertical
            // step-down (the synthetic 0%-drop we draw at every reset)
            // would render on top of the indigo line at the same x and
            // hide it.

            // 5h actual usage. The `series:` parameter is critical:
            // without it, Swift Charts groups same-axis LineMarks into
            // one visual series and collapses per-mark .foregroundStyle
            // modifiers to a shared color.
            ForEach(Array(line5h.enumerated()), id: \.offset) { _, p in
                LineMark(
                    x: .value("t", p.time),
                    y: .value("pct", p.value),
                    series: .value("kind", "actual5h"))
                .foregroundStyle(ChartPalette.actual5h)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }

            // Weekly actual usage — teal, only on 1w. Sits on the same
            // 0–100% axis as the 5h line, so the two lines stack
            // naturally: weekly is the slow climb, 5h is the saw-tooth
            // that dives on every reset.
            if showsWeekLine {
                ForEach(visible, id: \.timestamp) { s in
                    LineMark(
                        x: .value("t", s.timestamp),
                        y: .value("pct", s.fractionWeek * 100),
                        series: .value("kind", "actualWeek"))
                    .foregroundStyle(ChartPalette.actualWeek)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }

            // Forecast — gray, dashed; dash gap encodes confidence.
            // Color stays constant so it never competes with the
            // green/teal of actuals.
            if showsForecast, let f = forecast {
                let dash = forecastDash(f)
                ForEach(Array(visibleForecast.enumerated()), id: \.offset) { _, p in
                    LineMark(
                        x: .value("t", p.time),
                        y: .value("pct", p.projectedFraction * 100),
                        series: .value("kind", "forecast"))
                    .foregroundStyle(ChartPalette.forecast)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: dash))
                }
            }

            // Reset boundaries — drawn LAST so they sit on top of the
            // green step-down vertices that would otherwise cover them.
            // Indigo dashed verticals; visually distinct from the gray
            // axis gridlines.
            ForEach(Array(resetMarks.enumerated()), id: \.offset) { _, t in
                RuleMark(x: .value("reset", t))
                    .foregroundStyle(ChartPalette.resetBoundary)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            }
        }
        .chartYScale(domain: 0...100)
        .chartXScale(domain: cutoff...xMax)
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisGridLine()
                AxisValueLabel(format: axisFormat, centered: false)
                    .font(.system(size: 9))
            }
        }
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text("\(v)%").font(.system(size: 9))
                    }
                }
            }
        }
        .frame(height: 90)
    }

    /// One point on the 5h line. The chart uses these to draw the actual
    /// usage curve — including synthetic step-down points at detected
    /// reset events so the line visibly drops to 0% at each boundary.
    private struct LinePoint {
        let time: Date
        let value: Double          // percent, 0–100
    }

    /// All 5h-window reset times that fall inside `range`. Combines
    /// THREE independent signals so we get precise timing for both
    /// historical and upcoming resets:
    ///
    ///   1. **Snapshot crossings (historical, precise).** Whenever a
    ///      consecutive snapshot pair (prev, curr) has
    ///      `curr.timestamp ≥ prev.resetTime5h`, the reset that prev
    ///      saw coming actually happened. The reset moment is exactly
    ///      `prev.resetTime5h` — not a midpoint estimate. This is
    ///      drop-magnitude-independent: it fires when the boundary is
    ///      crossed, regardless of how full the window was.
    ///
    ///   2. **API's current upcoming reset (`nextReset5h`).** The
    ///      reset the user is heading toward right now.
    ///
    ///   3. **`nextReset5h + 5h` (next-but-one).** Useful on the
    ///      8h/24h chart where the right edge can extend past the
    ///      first reset; under continued activity this is exactly
    ///      where the next-but-one boundary lands.
    ///
    /// CRITICAL: We do NOT enumerate past resets by stepping
    /// `nextReset5h - 5h × k` backward. Anthropic's 5h window is a
    /// rolling window — when the user is idle, `resets_at` slides
    /// forward indefinitely, so subtracting 5h would point to
    /// fictitious past times where no reset actually happened.
    /// Snapshot crossings (signal #1) is the only safe way to
    /// reconstruct historical resets.
    private func fiveHourResetTimes(in range: ClosedRange<Date>,
                                    snapshots: [UsageSnapshot]) -> [Date] {
        var marks: [Date] = []

        // Signal #1 — historical resets. The reset time recorded
        // by `prev` has been crossed by `curr.timestamp`. Use
        // prev.resetTime5h as the reset's exact timestamp.
        for (prev, curr) in zip(snapshots, snapshots.dropFirst()) {
            if curr.timestamp >= prev.resetTime5h,
               range.contains(prev.resetTime5h) {
                marks.append(prev.resetTime5h)
            }
        }

        // Signals #2 and #3 — upcoming and next-but-one from API.
        if let next = nextReset5h {
            if range.contains(next) { marks.append(next) }
            let afterNext = next.addingTimeInterval(5 * 3600)
            if range.contains(afterNext) { marks.append(afterNext) }
        }

        // Dedupe (a snapshot crossing right at the API's nextReset5h
        // would otherwise produce two markers at nearly the same x).
        return Array(Set(marks)).sorted()
    }

    /// Weekly reset marker — at most one inside the visible 1w range,
    /// since the 7-day cycle barely fits more than once in a 1w view.
    private func weeklyResetMarks(in range: ClosedRange<Date>) -> [Date] {
        guard let next = nextResetWeek else { return [] }
        return range.contains(next) ? [next] : []
    }

    /// Build the chart points for the 5h line, inserting a synthetic
    /// vertical drop at every reset time that lands BETWEEN two
    /// consecutive snapshots. Drops happen at the exact API reset
    /// time — same x as the indigo RuleMark — so the green descent
    /// and the indigo guide visually coincide.
    ///
    /// Result for snapshot A (47%) at 23:55, reset at 00:23, snapshot
    /// B (1%) at 00:25:
    ///
    ///   [..., (23:55, 47),
    ///         (00:22:59.999, 47),   ← held until just before reset
    ///         (00:23, 0),           ← drop at exact reset time
    ///         (00:25, 1), ...]
    ///
    /// Idle case: if the prior snapshot is already at ≈0%, no synthetic
    /// drop is added — the line is already flat at 0 and an extra pair
    /// of points would just clutter the data series.
    private func augmented5hLine(_ snapshots: [UsageSnapshot],
                                 resets: [Date]) -> [LinePoint] {
        var out: [LinePoint] = []
        let sortedResets = resets.sorted()
        var resetIdx = 0
        for i in 0..<snapshots.count {
            let s = snapshots[i]
            if i > 0 {
                let prev = snapshots[i-1]
                // Insert a vertical drop for every reset strictly
                // between prev and s.
                while resetIdx < sortedResets.count {
                    let r = sortedResets[resetIdx]
                    if r <= prev.timestamp { resetIdx += 1; continue }
                    if r >= s.timestamp { break }
                    if prev.fraction5h > 0.001 {
                        out.append(LinePoint(
                            time: r.addingTimeInterval(-0.001),
                            value: prev.fraction5h * 100))
                        out.append(LinePoint(time: r, value: 0))
                    }
                    resetIdx += 1
                }
            }
            out.append(LinePoint(time: s.timestamp, value: s.fraction5h * 100))
        }
        return out
    }

    /// Pick an x-axis label format that matches the timeframe granularity.
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

    /// Map forecast confidence to a dash pattern. The visual axis is
    /// "solidity" — tighter dashes read as "more credible projection,"
    /// sparser dashes read as "less actionable / lower confidence."
    ///
    /// Same backend distinction as before, just encoded in stroke style
    /// instead of color:
    ///   • [5, 2] near-solid       = projected hit, R² ≥ 0.5
    ///   • [3, 4] moderate gap     = projected hit, R² < 0.5 (low conf)
    ///   • [2, 6] sparse dotted    = no projected hit (stable / won't reach)
    private func forecastDash(_ f: ForecastResult) -> [CGFloat] {
        if f.projectedHitTime != nil {
            return f.isLowConfidence ? [3, 4] : [5, 2]
        }
        return [2, 6]
    }
}
