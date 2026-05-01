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
        // Extend x-axis right edge to include any forward forecast.
        let forecastEnd = forecast?.line.last?.time ?? now
        let xMax = max(now, forecastEnd)
        let visible = snapshots.filter { $0.timestamp >= cutoff }
        let resets = resetTimes(in: cutoff...xMax)

        Chart {
            // 5h reset boundaries — gray dashed verticals.
            // Approximation: assume regular 5h spacing back from the
            // current window's resetAt. Real rolling windows can shift,
            // but without server-side history this is the best we have.
            ForEach(Array(resets.enumerated()), id: \.offset) { _, t in
                RuleMark(x: .value("reset", t))
                    .foregroundStyle(Color.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
            }

            ForEach(visible, id: \.timestamp) { s in
                LineMark(
                    x: .value("t", s.timestamp),
                    y: .value("pct", s.fraction5h * 100))
                .foregroundStyle(.green)
            }
            if let f = forecast {
                ForEach(Array(f.line.enumerated()), id: \.offset) { _, p in
                    LineMark(
                        x: .value("t", p.time),
                        y: .value("pct", p.projectedFraction * 100))
                    .foregroundStyle(.orange)
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
}
