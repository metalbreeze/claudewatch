import SwiftUI
import UsageCore

struct ForecastCaptionView: View {
    let forecast: ForecastResult?

    var body: some View {
        if let f = forecast, let hit = f.projectedHitTime {
            let df: DateFormatter = {
                let d = DateFormatter()
                d.timeStyle = .short
                return d
            }()
            let label = f.isLowConfidence
                ? "⏱ ~\(df.string(from: hit)) (low confidence)"
                : "⏱ likely full at \(df.string(from: hit))"
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        } else if forecast != nil {
            Text("⏱ stable, no projection").font(.system(size: 11)).foregroundStyle(.secondary)
        } else {
            Text("⏱ Building forecast…").font(.system(size: 11)).foregroundStyle(.tertiary)
        }
    }
}
