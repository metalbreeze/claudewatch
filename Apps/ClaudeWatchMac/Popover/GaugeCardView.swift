import SwiftUI

/// One of the two gauge cards at the top of the popover (5h / Week).
///
/// Visual layering, from least to most prominent:
///
///   • small label ("5H" / "WEEK")  — tinted with the metric color,
///                                     so it implicitly legends the chart
///                                     line below
///   • big percentage number        — danger-encoded:
///                                       <75%   default
///                                       75-89% yellow
///                                       ≥90%   red
///   • fill bar                     — solid metric color, width = percent.
///                                     Identity color, not danger color.
///   • reset caption                — tertiary text, unstyled
///
/// Decoupling identity (label + fill) from danger (number) means the
/// fill bars don't all turn green at low usage — each metric keeps its
/// own colour even when nothing is alarming.
struct GaugeCardView: View {
    let label: String
    let percent: Double          // 0..1
    let resetCaption: String
    /// Identity color for this metric — drives the label tint and the
    /// fill bar color. Sourced from `ChartPalette` so all UI surfaces
    /// stay coherent.
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
            Text("\(Int(percent * 100))%")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(dangerStyle(for: percent))
            FillBar(percent: percent, color: tint)
            Text(resetCaption)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.1))
        )
    }

    /// Percentage number color = danger signal:
    ///   • below 75%  — default primary text color (no alarm)
    ///   • 75 to <90% — yellow (warning)
    ///   • 90% and up — red (critical)
    /// AnyShapeStyle wrapping is needed because the ternary mixes
    /// HierarchicalShapeStyle (.primary) with concrete Colors.
    private func dangerStyle(for p: Double) -> AnyShapeStyle {
        if p >= 0.9 { return AnyShapeStyle(Color.red) }
        if p >= 0.75 { return AnyShapeStyle(Color.yellow) }
        return AnyShapeStyle(HierarchicalShapeStyle.primary)
    }
}

private struct FillBar: View {
    let percent: Double          // 0..1
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.25))
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: max(0, min(1, percent)) * geo.size.width)
            }
        }
        .frame(height: 4)
    }
}
