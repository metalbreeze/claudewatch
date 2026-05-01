import SwiftUI

struct GaugeCardView: View {
    let label: String
    let percent: Double          // 0..1
    let resetCaption: String
    /// Optional accent color for the small label ("5H" / "WEEK"). When
    /// set, this becomes an implicit chart legend — the user sees the
    /// label tint and matches it to the line color in the chart below.
    var labelTint: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(labelStyle)
            Text("\(Int(percent * 100))%")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
            // Pure-SwiftUI fill bar. ProgressView on macOS uses
            // NSProgressIndicator under the hood, which doesn't render its
            // tint inside an NSPopover until first interaction.
            FillBar(percent: percent, color: color(for: percent))
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

    private func color(for p: Double) -> Color {
        if p >= 0.9 { return .red }
        if p >= 0.75 { return .orange }
        return .green
    }

    /// `foregroundStyle` accepts any ShapeStyle; we wrap whichever variant
    /// applies into AnyShapeStyle so the ternary type-checks cleanly.
    private var labelStyle: AnyShapeStyle {
        if let tint = labelTint { return AnyShapeStyle(tint) }
        return AnyShapeStyle(HierarchicalShapeStyle.secondary)
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
