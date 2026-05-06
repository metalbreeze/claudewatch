import SwiftUI

/// Color scale for the 1-month heatmap cells. Single source of truth
/// so HeatmapView and any future overlay/legend stay visually
/// consistent.
///
/// Encoding rationale:
///   • Green base — heatmap intensity uses the same 5h-line color
///     family from ChartPalette, so the heatmap reads as part of
///     the same visualization story.
///   • Linear opacity ramp from 0.05 (visible-but-faint) to 0.85
///     (saturated). Pure 0% becomes a near-empty cell rather than a
///     fully transparent one — the user still sees "we have data
///     here, it was just empty" instead of "no data at all".
///   • ≥ 90% jumps to orange, matching the warning color GaugeCardView
///     uses for ≥ 75% on the 5h gauge. Visual continuity is intentional
///     — the user's "danger" reading should be the same across views.
///   • nil (no data) returns a faint gray border tone, distinguishing
///     "unpolled" from "polled but idle".
enum HeatmapPalette {
    static func cellColor(_ fraction: Double?) -> Color {
        guard let f = fraction else { return Color.gray.opacity(0.15) }
        if f >= 0.9 { return Color.orange.opacity(0.85) }
        return Color.green.opacity(0.05 + min(f, 0.9) * 0.85)
    }
}
