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
                let ok = await HiddenChallengeView.refreshClearance(
                    into: ctx.cookieStore, currentDeviceID: ctx.deviceID)
                if ok {
                    try? await c.pollOnce()
                    render()
                } else {
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
            statusItem.setText("⌬ —", tooltip: String(localized: "status.tooltip.noData",
                defaultValue: "No data"))
            return
        }
        let pct = Int(snap.fraction5h * 100)
        let weekPct = Int(snap.fractionWeek * 100)
        statusItem.setText(
            "⌬ \(pct)%",
            tooltip: String(localized: "status.tooltip.usage \(pct) \(weekPct)" as String.LocalizationValue))
    }
}

struct NotificationSinkAdapter: AlertSink {
    let dispatcher: NotificationDispatcher
    func deliver(_ k: AlertKind, snapshot s: UsageSnapshot, forecast f: ForecastResult?) async {
        await dispatcher.deliver(k, snapshot: s, forecast: f)
    }
}
