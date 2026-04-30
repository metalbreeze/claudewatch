import SwiftUI

struct GaugeCardView: View {
    let label: String
    let percent: Double          // 0..1
    let resetCaption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("\(Int(percent * 100))%")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
            ProgressView(value: percent)
                .progressViewStyle(.linear)
                .tint(color(for: percent))
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
}
