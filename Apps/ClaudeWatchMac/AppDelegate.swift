import AppKit
import UsageCore

/// AppKit lifecycle entry point for the menu bar app. Builds `AppContext`,
/// shows the (stub) login window if needed, and starts the polling loop.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var ctx: AppContext!
    var statusItem: StatusItemController!
    var popover: PopoverController?

    func applicationDidFinishLaunching(_ n: Notification) {
        do {
            ctx = try AppContext()
            statusItem = StatusItemController()
            // Registered once here — applicationDidFinishLaunching runs
            // exactly once per app launch (an AppKit guarantee), unlike
            // startPolling() below, which reruns on every cURL re-import.
            // Registering it there would pile up a duplicate observer per
            // re-import with no matching removeObserver.
            NotificationCenter.default.addObserver(
                forName: .menuBarDisplayOptionsChanged, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.render() }
            }
            // Wire menu actions early so they work even before login.
            statusItem.onSettings = { [weak self] in
                guard let self else { return }
                SettingsWindowController.show(ctx: self.ctx)
            }
            statusItem.onImportCURL = { [weak self] in
                guard let self else { return }
                CURLImportWindowController.show(ctx: self.ctx) { [weak self] in
                    self?.startPolling()
                }
            }
            if (try? ctx.cookieStore.load()) == nil {
                // Default to the cURL-paste flow rather than the
                // (mostly broken) embedded WKWebView login.
                statusItem.setText("⌬ ⏳", tooltip: String(localized: "status.tooltip.initializing",
                    defaultValue: "Right-click → Import from cURL…"))
                CURLImportWindowController.show(ctx: ctx) { [weak self] in
                    self?.startPolling()
                }
            } else {
                startPolling()
            }
        } catch {
            statusItem = StatusItemController()
            statusItem.setText("⌬ ⚠", tooltip: String(localized: "status.tooltip.initFailed \(error)" as String.LocalizationValue))
        }
    }

    private func startPolling() {
        // Reset any previous timer so re-imports cleanly restart polling.
        ctx.pollingTimer?.stop()
        ctx.pollingTimer = nil

        Task { @MainActor in
            guard let pkg = try? ctx.cookieStore.load() else {
                statusItem.setText("⌬ ⚠", tooltip: String(localized: "status.tooltip.notSignedIn",
                    defaultValue: "Not signed in — right-click → Import from cURL…"))
                return
            }
            // Load persisted endpoint URL from settings (set by cURL import).
            let endpointURL = (try? ctx.settings.get(.endpointConfig))
                .flatMap { $0 }
                .flatMap(URL.init(string:))
            let endpoint = EndpointConfig(jsonEndpoint: endpointURL)
            let factory = ScraperFactory(config: endpoint, cookies: pkg)
            let dispatcher = NotificationDispatcher()
            Task { _ = await dispatcher.requestAuthorization() }
            ctx.controller = UsageController(
                scraper: factory.current(),
                snapshots: ctx.snapshots,
                forecaster: LinearForecaster(),
                sync: nil,
                alertEngine: AlertEngine(),
                alertState: ctx.alertState,
                alertSink: NotificationSinkAdapter(dispatcher: dispatcher))
            let timer = PollingTimer(interval: 90, jitter: 10)
            timer.onTick = { [weak self] in Task { @MainActor in await self?.tick() } }
            timer.start()
            ctx.pollingTimer = timer
            popover = PopoverController(ctx: ctx)
            statusItem.onClick = { [weak self] in
                guard let self, let button = self.statusItem.item.button else { return }
                self.popover?.toggle(from: button)
            }
            await tick()  // immediate first poll
        }
    }

    @MainActor
    private func tick() async {
        guard let c = ctx.controller else { return }
        do {
            try await c.pollOnce()
            render()
        } catch let e as ScrapeError {
            if e.requiresWebViewRefresh {
                // Mark recovery in flight so the popover renders an
                // "auto-refreshing…" block instead of the stale
                // error message during the 2–10 s WKWebView load.
                c.setRecovering(true)
                let ok = await HiddenChallengeView.refreshClearance(
                    into: ctx.cookieStore, currentDeviceID: ctx.deviceID)
                c.setRecovering(false)
                if ok {
                    // pollOnce on success will reset
                    // consecutiveRecoveryFailures back to 0.
                    try? await c.pollOnce()
                    render()
                } else {
                    // Auto-refresh failed (rare — usually means the
                    // sessionKey itself is dead, not just CF cookies).
                    // Bump the counter; the popover uses this to
                    // decide between "still trying" and "needs you to
                    // re-import the cURL".
                    c.recordRecoveryFailure()
                    statusItem.setText("⌬ ⚠", tooltip: String(localized: "status.tooltip.cloudflareUnrecoverable",
                        defaultValue: "Cloudflare challenge unrecoverable"))
                }
            } else if e.isAuthRelated {
                statusItem.setText("⌬ ⚠", tooltip: String(localized: "status.tooltip.sessionExpired",
                    defaultValue: "Session expired — open app to re-login"))
            } else {
                statusItem.setText("⌬ ⚠", tooltip: "\(e)")
            }
        } catch {
            statusItem.setText("⌬ ⚠", tooltip: "\(error)")
        }
    }

    private func render() {
        guard let snap = ctx.controller?.state.latest else {
            // Distinct from "⌬" with no digits, which means the user
            // switched every segment off. This one means the first poll
            // hasn't come back yet.
            statusItem.setText("⌬ —", tooltip: String(localized: "status.tooltip.noData",
                defaultValue: "No data"))
            return
        }
        let segments = MenuBarFormatter.segments(snapshot: snap, options: menuBarOptions())
        let title = segments.isEmpty ? "⌬" : "⌬ \(segments)"

        // The tooltip always carries all three values, whatever the
        // menu bar is set to show: the bar is what the user chose to
        // watch, the tooltip is the full picture.
        let pct = Int(snap.fraction5h * 100)
        let weekPct = Int(snap.fractionWeek * 100)
        let tooltip: String
        if let fable = snap.fractionFable {
            let fablePct = Int(fable * 100)
            tooltip = String(localized:
                "status.tooltip.usageWithFable \(pct) \(weekPct) \(fablePct)"
                as String.LocalizationValue)
        } else {
            tooltip = String(localized:
                "status.tooltip.usage \(pct) \(weekPct)" as String.LocalizationValue)
        }
        statusItem.setText(title, tooltip: tooltip)
    }

    /// Reads the four persisted menu bar checkboxes. Falls back to
    /// `MenuBarDisplayOptions.default` field by field, so a database
    /// that predates these keys still renders sensibly.
    private func menuBarOptions() -> MenuBarDisplayOptions {
        let d = MenuBarDisplayOptions.default
        return MenuBarDisplayOptions(
            show5h:     (try? ctx.settings.getBool(.menuBarShow5h,     default: d.show5h))     ?? d.show5h,
            showWeek:   (try? ctx.settings.getBool(.menuBarShowWeek,   default: d.showWeek))   ?? d.showWeek,
            showFable:  (try? ctx.settings.getBool(.menuBarShowFable,  default: d.showFable))  ?? d.showFable,
            showLabels: (try? ctx.settings.getBool(.menuBarShowLabels, default: d.showLabels)) ?? d.showLabels)
    }
}

struct NotificationSinkAdapter: AlertSink {
    let dispatcher: NotificationDispatcher
    func deliver(_ k: AlertKind, snapshot s: UsageSnapshot, forecast f: ForecastResult?) async {
        await dispatcher.deliver(k, snapshot: s, forecast: f)
    }
}

extension Notification.Name {
    /// Posted by AppearancePane after any menu bar checkbox changes.
    ///
    /// Without it the menu bar would only pick up a new setting on the
    /// next poll — up to 90 seconds of staring at a checkbox that
    /// appears to do nothing.
    static let menuBarDisplayOptionsChanged = Notification.Name("menuBarDisplayOptionsChanged")
}
