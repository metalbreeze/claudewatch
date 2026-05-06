import SwiftUI
import GRDB
import UsageCore

struct PopoverRootView: View {
    @ObservedObject var controller: UsageController
    @State private var timeframe: Timeframe = .eightHour
    @State private var snapshots: [UsageSnapshot] = []
    /// `nil` follows the system appearance; `.light` / `.dark` overrides it.
    /// Sourced from SettingsRepository.theme by PopoverController and
    /// passed in fresh on every popover open.
    let preferredScheme: ColorScheme?
    /// Invoked when the user taps the "Re-import cURL" button shown
    /// inside the error block. The host app opens the
    /// CURLImportWindow; the popover stays out of AppKit specifics.
    let onReimport: () -> Void

    /// Recovery / error display branches. Resolved inside the body so
    /// SwiftUI re-evaluates whenever any of the underlying state
    /// changes (lastError, isRecovering, consecutiveRecoveryFailures).
    private enum DisplayState {
        case ok
        case autoRefreshing                       // CF cookies being refreshed in background
        case cloudflareTransient                  // CF error but auto-refresh hasn't given up yet
        case cloudflarePersistent                 // ≥3 auto-refresh failures — needs manual re-import
        case authExpired                          // sessionKey itself is dead, not just CF cookies
        case otherError(ScrapeError)              // network / rate-limit / schema-drift / unknown
    }
    private var displayState: DisplayState {
        // While auto-refresh is in flight, show that — even if a
        // stale cloudflareChallenge error is still recorded as
        // lastError from the failed poll that triggered it.
        if controller.state.isRecovering { return .autoRefreshing }
        guard let err = controller.state.lastError else { return .ok }
        switch err {
        case .cloudflareChallenge:
            return controller.state.consecutiveRecoveryFailures >= 3
                ? .cloudflarePersistent
                : .cloudflareTransient
        case .authExpired:
            return .authExpired
        default:
            return .otherError(err)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("popover.header.title")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(controller.state.latest?.plan.displayName ?? "—")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            // Status / error block. Surfaces the current recovery or
            // error state inside the popover instead of hiding it
            // behind the menu bar tooltip. The block changes shape
            // based on what the user can do:
            //   • auto-refreshing  → wait, no action
            //   • CF transient     → wait, no action ("we'll auto-fix")
            //   • CF persistent    → button to re-import cURL
            //   • auth expired     → button to re-import cURL
            //   • other            → just diagnostic text (network etc.)
            statusOrErrorBlock

            HStack(spacing: 10) {
                // Tints mirror the chart line colors so the gauge cards
                // double as an implicit chart legend: green "5H" + green
                // fill ↔ green line; teal "WEEK" + teal fill ↔ teal line.
                // Danger is encoded separately in the percentage number
                // (yellow ≥ 75%, red ≥ 90%) — see GaugeCardView.
                GaugeCardView(label: String(localized: "popover.gauge.5h", defaultValue: "5h"),
                    percent: controller.state.latest?.fraction5h ?? 0,
                    resetCaption: resetCaption(controller.state.latest?.resetTime5h),
                    tint: ChartPalette.actual5h)
                GaugeCardView(label: String(localized: "popover.gauge.week", defaultValue: "Week"),
                    percent: controller.state.latest?.fractionWeek ?? 0,
                    resetCaption: weeklyResetCaption(controller.state.latest?.resetTimeWeek),
                    tint: ChartPalette.actualWeek)
            }

            TimeframePicker(selection: $timeframe)
            LineChartView(snapshots: snapshots,
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
        // Force an opaque background so the popover stops being
        // translucent over the desktop. Color(.windowBackgroundColor)
        // is a dynamic system color: dark gray in dark mode, near-white
        // in light mode — so the gauges/text/chart stay legible against
        // whatever the user has behind their menu bar.
        .background(Color(.windowBackgroundColor))
        // Override system appearance per the Settings → Appearance pick.
        // nil = follow system; .light / .dark = force.
        .preferredColorScheme(preferredScheme)
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
        let hours = s / 3600
        let minutes = (s / 60) % 60
        return String(localized: "popover.reset.resetsIn \(hours) \(minutes)" as String.LocalizationValue)
    }

    private func weeklyResetCaption(_ d: Date?) -> String {
        guard let d else { return "—" }
        let df = DateFormatter(); df.dateFormat = "E"
        let day = df.string(from: d)
        return String(localized: "popover.reset.resetsOn \(day)" as String.LocalizationValue)
    }

    // MARK: - Status / error block

    @ViewBuilder
    private var statusOrErrorBlock: some View {
        switch displayState {
        case .ok:
            EmptyView()
        case .autoRefreshing:
            statusBanner(
                tone: .info,
                title: String(localized: "popover.recovery.refreshing.title",
                              defaultValue: "Auto-refreshing Cloudflare cookies…"),
                body: String(localized: "popover.recovery.refreshing.body",
                              defaultValue: "Usually takes 5–10 seconds. The popover will update automatically."))
        case .cloudflareTransient:
            statusBanner(
                tone: .warning,
                title: String(localized: "popover.recovery.cloudflareTransient.title",
                              defaultValue: "Cloudflare challenge"),
                body: String(localized: "popover.recovery.cloudflareTransient.body",
                              defaultValue: "Will auto-refresh on the next poll cycle (≈ 90 s)."))
        case .cloudflarePersistent:
            statusBanner(
                tone: .error,
                title: String(localized: "popover.recovery.cloudflarePersistent.title",
                              defaultValue: "Cloudflare challenge persists"),
                body: String(localized: "popover.recovery.cloudflarePersistent.body",
                              defaultValue: "Auto-refresh failed several times. Re-import a fresh cURL from your browser to refresh all cookies."),
                action: (label: String(localized: "popover.action.reimport",
                                       defaultValue: "Re-import cURL…"),
                         handler: onReimport))
        case .authExpired:
            statusBanner(
                tone: .error,
                title: String(localized: "popover.recovery.authExpired.title",
                              defaultValue: "Claude.ai session expired"),
                body: String(localized: "popover.recovery.authExpired.body",
                              defaultValue: "Sign in to claude.ai in your browser, then re-import the cURL."),
                action: (label: String(localized: "popover.action.reimport",
                                       defaultValue: "Re-import cURL…"),
                         handler: onReimport))
        case .otherError(let err):
            statusBanner(
                tone: .error,
                title: String(localized: "popover.error.lastPollFailed",
                              defaultValue: "Last poll failed"),
                body: rawErrorBody(err))
        }
    }

    private enum BannerTone {
        case info, warning, error
        var color: Color {
            switch self {
            case .info: return .accentColor
            case .warning: return .orange
            case .error: return .red
            }
        }
    }

    @ViewBuilder
    private func statusBanner(tone: BannerTone,
                              title: String,
                              body: String,
                              action: (label: String, handler: () -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tone.color)
            Text(body)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(4)
            if let action {
                Button(action: action.handler) {
                    Text(action.label)
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .padding(.top, 2)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    /// Diagnostic text for errors that don't have a dedicated UX
    /// branch (network, rate-limited, schema drift, unknown). Kept in
    /// monospaced presentation since users sometimes copy these into
    /// bug reports.
    private func rawErrorBody(_ e: ScrapeError) -> String {
        switch e {
        case .authExpired, .cloudflareChallenge:
            // Handled by dedicated banners above.
            return ""
        case .schemaDrift(let v, let payload):
            let preview = String(data: payload.prefix(200), encoding: .utf8) ?? "(unreadable)"
            return String(localized: "popover.error.schemaDrift \(v) \(preview)" as String.LocalizationValue)
        case .network(let url):
            return String(localized: "popover.error.network \(url.code.rawValue) \(url.localizedDescription)" as String.LocalizationValue)
        case .rateLimited(let retry):
            let retryStr = retry.map { "\(Int($0))s" } ?? "—"
            return String(localized: "popover.error.rateLimited \(retryStr)" as String.LocalizationValue)
        case .unknown(let s):
            return s
        }
    }
}
