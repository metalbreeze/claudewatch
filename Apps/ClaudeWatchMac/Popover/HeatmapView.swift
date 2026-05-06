import SwiftUI
import UsageCore

/// 6 × 28 cell heatmap covering the most recent 28 days. Each row
/// is a 4-hour slot of local-time-of-day (00–04 … 20–24); each
/// column is one day, with today on the right.
///
/// Cell color encodes max(fraction5h) within that bucket — see
/// docs/superpowers/specs/2026-05-06-onemonth-heatmap-design.md.
///
/// Drawn with SwiftUI Canvas instead of Charts.RectangleMark for:
///   • pixel-precise cell sizing (10.2 × 16 pt with 1 pt gaps)
///   • single-pass GraphicsContext fill instead of 168 view nodes
///   • room to add custom hover/tap tooltips later without fighting
///     Charts' chartProxy layer
struct HeatmapView: View {
    let snapshots: [UsageSnapshot]

    private static let dateLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()

    /// Pulled from `HeatmapBucket` so the renderer never silently
    /// diverges from the bucketing logic in UsageCore.
    private let days = HeatmapBucket.dayCount
    /// Pulled from `HeatmapBucket` so the renderer never silently
    /// diverges from the bucketing logic in UsageCore.
    private let slots = 24 / HeatmapBucket.slotHours
    /// Reserved width on the left of the canvas for hour-of-day
    /// labels (00, 04, 08, 12, 16, 20).
    private let leftAxisWidth: CGFloat = 24
    /// Reserved height at the top for sparse date labels.
    private let topLabelHeight: CGFloat = 14

    var body: some View {
        Canvas { ctx, size in
            let now = Date()
            let buckets = HeatmapBucket.bucketize(snapshots, now: now)

            let gridOriginX = leftAxisWidth
            let gridOriginY = topLabelHeight + 2
            let gridWidth   = size.width  - leftAxisWidth
            let gridHeight  = size.height - topLabelHeight - 2

            let cellW = gridWidth  / CGFloat(days)
            let cellH = gridHeight / CGFloat(slots)
            let gap: CGFloat = 1

            // 1. Cell rectangles.
            for day in 0..<days {
                for slot in 0..<slots {
                    let key = HeatmapBucket(dayIndex: day, slotIndex: slot)
                    let value = buckets[key]
                    let color = HeatmapPalette.cellColor(value)
                    let rect = CGRect(
                        x: gridOriginX + CGFloat(day) * cellW + gap / 2,
                        y: gridOriginY + CGFloat(slot) * cellH + gap / 2,
                        width:  cellW - gap,
                        height: cellH - gap)
                    ctx.fill(Path(rect), with: .color(color))
                }
            }

            // 2. Left-axis hour labels — show every 4 hours (00, 04,
            // 08, 12, 16, 20) regardless of slot size, so labels never
            // crowd. Stride is "labels per 4 hours" = 4 / slotHours.
            let labelStride = max(1, 4 / HeatmapBucket.slotHours)
            for slot in stride(from: 0, to: slots, by: labelStride) {
                let label = String(format: "%02d", slot * HeatmapBucket.slotHours)
                let text = Text(label)
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                let resolved = ctx.resolve(text)
                let textSize = resolved.measure(in: CGSize(width: leftAxisWidth,
                                                           height: cellH * CGFloat(labelStride)))
                let textOrigin = CGPoint(
                    x: leftAxisWidth - textSize.width - 2,
                    y: gridOriginY + CGFloat(slot) * cellH + (cellH - textSize.height) / 2)
                ctx.draw(resolved, at: textOrigin, anchor: .topLeading)
            }

            // 3. Sparse top-axis date labels — every 7th day.
            let cal = Calendar.current
            for day in stride(from: 0, to: days, by: 7) {
                let dayOffset = -(days - 1 - day)
                guard let date = cal.date(byAdding: .day, value: dayOffset, to: now) else { continue }
                let text = Text(Self.dateLabelFormatter.string(from: date))
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                let resolved = ctx.resolve(text)
                let textSize = resolved.measure(in: CGSize(width: cellW * 7,
                                                           height: topLabelHeight))
                let textOrigin = CGPoint(
                    x: gridOriginX + CGFloat(day) * cellW,
                    y: 0)
                ctx.draw(resolved, at: textOrigin, anchor: .topLeading)
            }
        }
        .frame(height: 140)
    }
}
