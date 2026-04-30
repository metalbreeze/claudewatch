import SwiftUI
import GRDB
import UsageCore

struct PopoverRootView: View {
    @ObservedObject var controller: UsageController
    @State private var timeframe: Timeframe = .oneHour
    @State private var snapshots: [UsageSnapshot] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CLAUDE USAGE")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(controller.state.latest?.plan.displayName ?? "—")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                GaugeCardView(label: "5h",
                    percent: controller.state.latest?.fraction5h ?? 0,
                    resetCaption: resetCaption(controller.state.latest?.resetTime5h))
                GaugeCardView(label: "Week",
                    percent: controller.state.latest?.fractionWeek ?? 0,
                    resetCaption: weeklyResetCaption(controller.state.latest?.resetTimeWeek))
            }

            TimeframePicker(selection: $timeframe)
            ChartView(snapshots: snapshots, forecast: controller.state.forecast, timeframe: timeframe)
            if timeframe == .oneHour || timeframe == .eightHour {
                ForecastCaptionView(forecast: controller.state.forecast)
            }
            FooterView(lastPollAt: controller.state.lastPollAt, onRefresh: {
                Task { try? await controller.pollOnce() }
            })
        }
        .padding(12)
        .frame(width: 340)
        .onAppear { refreshSnapshots() }
        .onChange(of: timeframe) { _ in refreshSnapshots() }
        .onChange(of: controller.state.lastPollAt) { _ in refreshSnapshots() }
    }

    private func refreshSnapshots() {
        // Task 39 wires this to a real history query.
        snapshots = controller.state.latest.map { [$0] } ?? []
    }

    private func resetCaption(_ d: Date?) -> String {
        guard let d else { return "—" }
        let s = max(0, Int(d.timeIntervalSinceNow))
        return "resets in \(s/3600)h \((s/60)%60)m"
    }
    private func weeklyResetCaption(_ d: Date?) -> String {
        guard let d else { return "—" }
        let df = DateFormatter(); df.dateFormat = "E"
        return "resets \(df.string(from: d))"
    }
}
