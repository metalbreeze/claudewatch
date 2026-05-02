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
        //   • 1h/8h/24h → indigo lines at REAL past resets (detected from
        //     drops in used_5h between consecutive snapshots) plus the
        //     upcoming reset from the API.
        //   • 1w → just the upcoming weekly reset (the saw-tooth pattern
        //     of the 5h line itself shows where rolling resets happened,
        //     so dotting the chart with ~33 markers is just noise).
        let resetMarks: [Date] = showsWeekLine
            ? weeklyResetMarks(in: cutoff...xMax)
            : fiveHourResetMarks(in: cutoff...xMax, snapshots: visible)
        // Augment the raw 5h snapshot stream with synthetic step-down
        // points at every detected reset so the line visibly drops to
        // 0% at the boundary instead of slanting smoothly across it.
        let line5h = augmented5hLine(visible)

        Chart {
            // Reset boundaries — indigo dashed verticals so they're
            // visually distinct from the gray axis gridlines.
            ForEach(Array(resetMarks.enumerated()), id: \.offset) { _, t in
                RuleMark(x: .value("reset", t))
                    .foregroundStyle(ChartPalette.resetBoundary)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            }

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
            // amber/teal of actuals.
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

    /// 5h-window resets we can prove from snapshot history: any time
    /// `used_5h` decreases between consecutive snapshots, a reset must
    /// have happened in the gap (used_5h is monotonically non-decreasing
    /// within a single window). Combined with the upcoming reset from
    /// the API, these are the only indigo guides we draw.
    ///
    /// Iterating with `zip(snapshots, snapshots.dropFirst())` instead of
    /// `1..<count` because the latter trap-crashes when `snapshots` is
    /// empty (Range requires lowerBound ≤ upperBound, and `1..<0` is
    /// invalid). zip is empty-safe by construction.
    private func fiveHourResetMarks(in range: ClosedRange<Date>,
                                    snapshots: [UsageSnapshot]) -> [Date] {
        var marks: [Date] = []
        for (prev, curr) in zip(snapshots, snapshots.dropFirst()) {
            if curr.used5h < prev.used5h {
                let mid = midpoint(prev.timestamp, curr.timestamp)
                if range.contains(mid) { marks.append(mid) }
            }
        }
        if let next = nextReset5h, range.contains(next) {
            marks.append(next)
        }
        return marks
    }

    /// Weekly reset marker — at most one inside the visible 1w range,
    /// since the 7-day cycle barely fits more than once in a 1w view.
    private func weeklyResetMarks(in range: ClosedRange<Date>) -> [Date] {
        guard let next = nextResetWeek else { return [] }
        return range.contains(next) ? [next] : []
    }

    /// Build the chart points for the 5h line, inserting synthetic
    /// step-down vertices around every detected reset. Result for a
    /// reset between snapshot A (47%) and snapshot B (2%):
    ///
    ///   [..., (A.t, 47), (mid - ε, 47), (mid, 0), (B.t, 2), ...]
    ///
    /// LineMark connects these in order, producing a near-flat hold
    /// followed by a vertical drop to 0, then a climb to B — which is
    /// what users intuit when they see "the 5h window just reset."
    private func augmented5hLine(_ snapshots: [UsageSnapshot]) -> [LinePoint] {
        var out: [LinePoint] = []
        for i in 0..<snapshots.count {
            let s = snapshots[i]
            if i > 0 {
                let prev = snapshots[i-1]
                if s.used5h < prev.used5h {
                    let mid = midpoint(prev.timestamp, s.timestamp)
                    out.append(LinePoint(
                        time: mid.addingTimeInterval(-0.001),
                        value: prev.fraction5h * 100))
                    out.append(LinePoint(time: mid, value: 0))
                }
            }
            out.append(LinePoint(time: s.timestamp, value: s.fraction5h * 100))
        }
        return out
    }

    private func midpoint(_ a: Date, _ b: Date) -> Date {
        Date(timeIntervalSince1970:
            (a.timeIntervalSince1970 + b.timeIntervalSince1970) / 2)
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
