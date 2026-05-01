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

            // Surface the last poll error inside the popover instead of
            // hiding it in the menu bar tooltip. The user can copy from
            // here when reporting issues.
            if let err = controller.state.lastError {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last poll failed")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.red)
                    Text(errorDescription(err))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(4)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }

            HStack(spacing: 10) {
                // Tints mirror the chart line colors so the gauge cards
                // double as an implicit chart legend: green "5H" + green
                // fill ↔ green line; teal "WEEK" + teal fill ↔ teal line.
                // Danger is encoded separately in the percentage number
                // (yellow ≥ 75%, red ≥ 90%) — see GaugeCardView.
                GaugeCardView(label: "5h",
                    percent: controller.state.latest?.fraction5h ?? 0,
                    resetCaption: resetCaption(controller.state.latest?.resetTime5h),
                    tint: ChartPalette.actual5h)
                GaugeCardView(label: "Week",
                    percent: controller.state.latest?.fractionWeek ?? 0,
                    resetCaption: weeklyResetCaption(controller.state.latest?.resetTimeWeek),
                    tint: ChartPalette.actualWeek)
            }

            TimeframePicker(selection: $timeframe)
            ChartView(snapshots: snapshots,
                      forecast: controller.state.forecast,
                      timeframe: timeframe,
                      nextReset5h: controller.state.latest?.resetTime5h,
                      nextResetWeek: controller.state.latest?.resetTimeWeek)
            // Show forecast caption on every timeframe except 1w. The
            // forecast is short-term and 5h-based; on the 7-day view we
            // plot fractionWeek instead, so the 5h-forecast caption
            // would mismatch the chart.
            if timeframe != .oneWeek {
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
        snapshots = (try? controller.snapshots(within: timeframe.seconds)) ?? []
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

    private func errorDescription(_ e: ScrapeError) -> String {
        switch e {
        case .authExpired:
            return "Session expired. Right-click → Import from cURL… to refresh."
        case .cloudflareChallenge:
            return "Cloudflare challenge. Cookies need refreshing."
        case .schemaDrift(let v, let payload):
            let preview = String(data: payload.prefix(200), encoding: .utf8) ?? "(unreadable)"
            return "Schema drift (\(v)). Response preview:\n\(preview)"
        case .network(let url):
            return "Network: \(url.code.rawValue) \(url.localizedDescription)"
        case .rateLimited(let retry):
            return "Rate-limited. Retry-after: \(retry.map { "\(Int($0))s" } ?? "—")"
        case .unknown(let s):
            return s
        }
    }
}
