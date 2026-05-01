import SwiftUI
import Charts
import UsageCore

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
        // Forecast is short-term and 5h-window-based — meaningful on 1h /
        // 8h / 24h. We don't have a separate "weekly forecast", so the 1w
        // view (which tracks the 7-day metric) doesn't draw it.
        let useWeeklyMetric = (timeframe == .oneWeek)
        let showsForecast = !useWeeklyMetric

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
        let resetMarks: [Date] = useWeeklyMetric
            ? weeklyResetMarks(in: cutoff...xMax)
            : fiveHourResetMarks(in: cutoff...xMax)

        Chart {
            // Reset boundaries — indigo dashed verticals so they're
            // visually distinct from the gray axis gridlines.
            ForEach(Array(resetMarks.enumerated()), id: \.offset) { _, t in
                RuleMark(x: .value("reset", t))
                    .foregroundStyle(Color.indigo.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            }

            // The `series:` parameter is critical: without it, Swift Charts
            // groups same-axis LineMarks into a single visual series and
            // collapses per-mark .foregroundStyle modifiers to a shared
            // color (which is why forecast was rendering green like
            // actual usage).
            ForEach(visible, id: \.timestamp) { s in
                LineMark(
                    x: .value("t", s.timestamp),
                    y: .value("pct", (useWeeklyMetric ? s.fractionWeek : s.fraction5h) * 100),
                    series: .value("kind", "actual"))
                .foregroundStyle(.green)
            }

            // Forecast line: only on 5h-window views. The forecaster is
            // computed from used_5h, so plotting it on a weekly view
            // would mix metrics.
            if showsForecast, let f = forecast {
                let tone = forecastTone(f)
                ForEach(Array(visibleForecast.enumerated()), id: \.offset) { _, p in
                    LineMark(
                        x: .value("t", p.time),
                        y: .value("pct", p.projectedFraction * 100),
                        series: .value("kind", "forecast"))
                    .foregroundStyle(tone.color)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
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

    /// Three-tier color hierarchy for the forecast line:
    ///   • gray         = informational (no projected hit, no action needed)
    ///   • lightOrange  = warning, low trust (hit projected but R² < 0.5)
    ///   • orange       = warning, trustworthy (hit projected, R² ≥ 0.5)
    private enum ForecastTone {
        case gray, lightOrange, orange

        var color: Color {
            switch self {
            case .gray:        return Color.gray.opacity(0.55)
            case .lightOrange: return Color.orange.opacity(0.45)
            case .orange:      return Color.orange
            }
        }
    }

    private func forecastTone(_ f: ForecastResult) -> ForecastTone {
        if f.projectedHitTime != nil {
            return f.isLowConfidence ? .lightOrange : .orange
        }
        return .gray
    }
}
