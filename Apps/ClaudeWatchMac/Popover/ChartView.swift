import SwiftUI
import Charts
import UsageCore

struct ChartView: View {
    let snapshots: [UsageSnapshot]
    let forecast: ForecastResult?
    let timeframe: Timeframe
    /// The next 5h-window reset time from the most recent snapshot. Used to
    /// stamp vertical guide lines on the chart so the user can see when
    /// each rolling 5h window ends, especially on 8h / 24h / 1w views
    /// that span multiple windows.
    let nextReset5h: Date?

    var body: some View {
        let now = Date()
        let cutoff = now.addingTimeInterval(-timeframe.seconds)
        // Cap how far the chart extends past now. Without this, an active
        // forecast that runs all the way to resetTime5h (potentially ~5h
        // away) would balloon the chart well past its labeled timeframe —
        // a 1h view would actually span 6h. Limiting future to 1/4 of the
        // timeframe keeps the x-axis label honest.
        let showsForecast = (timeframe == .oneHour || timeframe == .eightHour)
        let maxFuture = timeframe.seconds * 0.25
        let forecastEnd = forecast?.line.last?.time ?? now
        let cappedEnd = min(forecastEnd, now.addingTimeInterval(maxFuture))
        let xMax = showsForecast ? max(now, cappedEnd) : now
        let visible = snapshots.filter { $0.timestamp >= cutoff }
        let resets = resetTimes(in: cutoff...xMax)
        // Forecast points clipped to the visible future window only.
        let visibleForecast = forecast?.line.filter { $0.time <= xMax } ?? []

        Chart {
            // 5h reset boundaries — indigo dashed verticals so they're
            // visually distinct from the gray axis gridlines. Approximation:
            // assume regular 5h spacing back from the current window's
            // resetAt. Real rolling windows can shift, but without
            // server-side history this is the best we have.
            ForEach(Array(resets.enumerated()), id: \.offset) { _, t in
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
                    y: .value("pct", s.fraction5h * 100),
                    series: .value("kind", "actual"))
                .foregroundStyle(.green)
            }

            // Only draw forecast on 1h / 8h views to match
            // ForecastCaptionView. 24h / 1w views are about historical
            // pattern, not short-term projection — adding a forecast
            // line there clutters more than it informs.
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

    /// Computes 5h-reset boundaries that fall inside the visible x-axis
    /// range, walking backward and forward from `nextReset5h` in 5-hour
    /// steps.
    private func resetTimes(in range: ClosedRange<Date>) -> [Date] {
        guard let next = nextReset5h else { return [] }
        var result: [Date] = []
        // Backward (past resets that still fall inside the window).
        var t = next
        while t >= range.lowerBound {
            if t <= range.upperBound { result.append(t) }
            t = t.addingTimeInterval(-5 * 3600)
        }
        // Forward (future resets if forecast extends past `next`).
        t = next.addingTimeInterval(5 * 3600)
        while t <= range.upperBound {
            result.append(t)
            t = t.addingTimeInterval(5 * 3600)
        }
        return result
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
