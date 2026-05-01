import SwiftUI
import UsageCore

/// Caption beneath the chart that summarises the current forecast state.
/// Wording is matched to the chart line so the user never sees "stable"
/// next to a visibly-rising line. Five states, mirroring the visual
/// matrix in `ChartView.ForecastTone`:
///
///   • forecast == nil                              → "Building forecast…"
///   • hit != nil, R² ≥ 0.5                         → "likely full at HH:MM"
///   • hit != nil, R²  < 0.5                        → "~HH:MM (low confidence)"
///   • hit == nil, slope >  0.0001                  → "won't hit limit this window"
///   • hit == nil, slope ≤ 0.0001                   → "stable"
struct ForecastCaptionView: View {
    let forecast: ForecastResult?

    var body: some View {
        Text(captionText)
            .font(.system(size: 11))
            .foregroundStyle(forecast == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
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

        // No projected hit. Disambiguate "stable" from "trending up but
        // won't reach the limit before this 5h window resets". The
        // 0.0001 threshold mirrors LinearForecaster's hit-time clamp,
        // so UI labels stay coherent with backend math.
        return f.slope > 0.0001
            ? "⏱ won't hit limit this window"
            : "⏱ stable"
    }
}
