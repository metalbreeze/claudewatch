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

        // Cap how far the chart extends past now. Without this, an active
        // forecast that runs all the way to resetTime5h (potentially ~5h
        // away) would balloon the chart well past its labeled timeframe —
        // a 1h view would actually span 6h. Limiting future to 1/4 of the
        // timeframe keeps the x-axis label honest.
        let maxFuture = timeframe.seconds * 0.25
        let forecastEnd = forecast?.line.last?.time ?? now
        let cappedEnd = min(forecastEnd, now.addingTimeInterval(maxFuture))
        let xMax = showsForecast ? max(now, cappedEnd) : now
        let visible = snapshots.filter { $0.timestamp >= cutoff }
        let visibleForecast = forecast?.line.filter { $0.time <= xMax } ?? []

        // Reset markers: on 1h/8h/24h, every 5h boundary inside the
        // window. On 1w, just the upcoming weekly reset (a single line).
        let resetMarks: [Date] = showsWeekLine
            ? weeklyResetMarks(in: cutoff...xMax)
            : fiveHourResetMarks(in: cutoff...xMax)

        Chart {
            // Reset boundaries — indigo dashed verticals so they're
            // visually distinct from the gray axis gridlines.
            ForEach(Array(resetMarks.enumerated()), id: \.offset) { _, t in
                RuleMark(x: .value("reset", t))
                    .foregroundStyle(ChartPalette.resetBoundary)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            }

            // 5h actual usage — orange, present on every timeframe.
            // The `series:` parameter is critical: without it, Swift Charts
            // groups same-axis LineMarks into a single visual series and
            // collapses per-mark .foregroundStyle modifiers to a shared
            // color.
            ForEach(visible, id: \.timestamp) { s in
                LineMark(
                    x: .value("t", s.timestamp),
                    y: .value("pct", s.fraction5h * 100),
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

    /// 5h-reset boundaries that fall inside the visible x-axis range,
    /// walking backward and forward from `nextReset5h` in 5-hour steps.
    private func fiveHourResetMarks(in range: ClosedRange<Date>) -> [Date] {
        guard let next = nextReset5h else { return [] }
        var result: [Date] = []
        var t = next
        while t >= range.lowerBound {
            if t <= range.upperBound { result.append(t) }
            t = t.addingTimeInterval(-5 * 3600)
        }
        t = next.addingTimeInterval(5 * 3600)
        while t <= range.upperBound {
            result.append(t)
            t = t.addingTimeInterval(5 * 3600)
        }
        return result
    }

    /// Weekly reset marker — at most one inside the visible 1w range,
    /// since the 7-day cycle barely fits more than once in a 1w view.
    private func weeklyResetMarks(in range: ClosedRange<Date>) -> [Date] {
        guard let next = nextResetWeek else { return [] }
        return (next >= range.lowerBound && next <= range.upperBound) ? [next] : []
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
