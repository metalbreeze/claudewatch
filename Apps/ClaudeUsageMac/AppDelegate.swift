import AppKit
import UsageCore

/// AppKit lifecycle entry point for the menu bar app. Builds `AppContext`,
/// shows the (stub) login window if needed, and starts the polling loop.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var ctx: AppContext!
    var statusItem: StatusItemController!

    func applicationDidFinishLaunching(_ n: Notification) {
        do {
            ctx = try AppContext()
            statusItem = StatusItemController()
            if (try? ctx.cookieStore.load()) == nil {
                LoginWindowController.show(ctx: ctx) { [weak self] in
                    self?.startPolling()
                }
            } else {
                startPolling()
            }
        } catch {
            statusItem = StatusItemController()
            statusItem.setText("⌬ ⚠", tooltip: "Init failed: \(error)")
        }
    }

    private func startPolling() {
        Task { @MainActor in
            // Without a discovered endpoint (Task 32), `ScraperFactory`
            // falls back to the HTML stub which throws — that's expected
            // until the endpoint is wired. The status item shows the
            // resulting error in its tooltip.
            guard let pkg = try? ctx.cookieStore.load() else {
                statusItem.setText("⌬ ⚠", tooltip: "Not signed in")
                return
            }
            let endpoint = EndpointConfig(jsonEndpoint: nil)
            let factory = ScraperFactory(config: endpoint, cookies: pkg)
            ctx.controller = UsageController(
                scraper: factory.current(),
                snapshots: ctx.snapshots,
                forecaster: LinearForecaster(),
                sync: nil)
            let timer = PollingTimer(interval: 90, jitter: 10)
            timer.onTick = { [weak self] in Task { @MainActor in await self?.tick() } }
            timer.start()
            ctx.pollingTimer = timer
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
            statusItem.setText("⌬ ⚠", tooltip: "\(e)")
        } catch {
            statusItem.setText("⌬ ⚠", tooltip: "\(error)")
        }
    }

    private func render() {
        guard let snap = ctx.controller?.state.latest else {
            statusItem.setText("⌬ —", tooltip: "No data")
            return
        }
        let pct = Int(snap.fraction5h * 100)
        statusItem.setText(
            "⌬ \(pct)%",
            tooltip: "5h: \(pct)% • Week: \(Int(snap.fractionWeek * 100))%")
    }
}
