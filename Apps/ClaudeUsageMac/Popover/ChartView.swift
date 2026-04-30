import SwiftUI
import Charts
import UsageCore

struct ChartView: View {
    let snapshots: [UsageSnapshot]
    let forecast: ForecastResult?
    let timeframe: Timeframe

    var body: some View {
        let cutoff = Date().addingTimeInterval(-timeframe.seconds)
        let visible = snapshots.filter { $0.timestamp >= cutoff }
        Chart {
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
        .frame(height: 90)
    }
}
