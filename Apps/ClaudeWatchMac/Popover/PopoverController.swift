import AppKit
import SwiftUI
import UsageCore

@MainActor
final class PopoverController: NSObject, NSPopoverDelegate {
    let popover = NSPopover()
    let ctx: AppContext

    /// Seconds the pointer must stay outside the popover before it closes.
    private static let autoHideAfter: TimeInterval = 10.0
    /// How often the idle check runs. Polling beats NSTrackingArea
    /// here: the popover rebuilds its SwiftUI content tree on every
    /// open, and tracking areas installed inside an NSHostingController
    /// don't survive that reliably. At 0.5 s the cost is nil.
    private static let idlePollInterval: TimeInterval = 0.5

    /// Fires while the popover is shown; closes it once the pointer has
    /// been away for `autoHideAfter`.
    private var idleTimer: Timer?
    private var idleElapsed: TimeInterval = 0
    /// Global monitors only see events delivered to OTHER applications,
    /// so clicks inside our own popover never reach this handler and no
    /// self-dismissal guard is needed.
    private var outsideClickMonitor: Any?

    init(ctx: AppContext) {
        self.ctx = ctx
        // Height grew 50 pt vs v0.1.8: chart frame went from 90 to
        // 140 pt to give the 1m heatmap room for ~16 pt × 6-row
        // cells. Other tabs share the same height so switching
        // tabs doesn't animate the popover's outer frame.
        popover.contentSize = NSSize(width: 340, height: 470)
        popover.behavior = .transient
        super.init()
        // Delegate hook so every AppKit-initiated close — not just the
        // ones we route through close() ourselves — tears down the
        // idle timer and outside-click monitor. See popoverDidClose.
        popover.delegate = self
        rebuildContent()
    }

    func toggle(from anchor: NSStatusBarButton) {
        if popover.isShown {
            close()
        } else {
            // Rebuild the SwiftUI tree on every open. Without this, the
            // segmented picker shows nothing selected and the gauge bars
            // stay empty until the first interaction inside the popover —
            // a known issue with SwiftUI inside NSPopover where the view
            // doesn't re-evaluate @ObservedObject changes while offscreen.
            rebuildContent()
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
            startDismissalWatchers()
        }
    }

    /// Single close path so the timer and monitor can never outlive the
    /// popover, no matter which dismissal trigger fired (outside click,
    /// idle timeout, re-clicking the status item, or re-importing a
    /// cURL from inside the popover). AppKit-initiated closes that
    /// don't go through this method — Escape, `.transient` auto-close
    /// on losing key to another window, right-click menu tracking, a
    /// Space switch — are caught by popoverDidClose below instead.
    func close() {
        stopDismissalWatchers()
        popover.performClose(nil)
    }

    /// Covers every dismissal AppKit initiates on its own rather than
    /// through close(): Escape while the popover is key, `.transient`
    /// auto-close when another window (Settings, the cURL import
    /// window reachable from the status-item right-click menu) takes
    /// key, right-click menu tracking, a Space switch. Without this
    /// hook those paths would leave the idle timer and outside-click
    /// monitor running after the popover is already gone.
    func popoverDidClose(_ notification: Notification) {
        // `popover.animates` defaults to true, so AppKit delivers this
        // notification AFTER the close animation finishes — not at the
        // moment the close was requested. If the user re-opens the
        // popover (rapid status-item toggling) while that animation is
        // still in flight, this is the STALE notification from the
        // previous open arriving after startDismissalWatchers() already
        // installed fresh watchers for the new open. Without this
        // guard we'd tear those fresh watchers down, leaving the
        // now-open popover with no idle timer and no outside-click
        // monitor. `isShown` is false only when this really is the
        // close it claims to be.
        guard !popover.isShown else { return }
        stopDismissalWatchers()
    }

    /// `.transient` alone doesn't dismiss this popover: in an
    /// LSUIElement process, clicking the status item doesn't activate
    /// the app, so the outside-click event that `.transient` waits for
    /// never arrives. Calling NSApp.activate would fix that but steals
    /// keyboard focus from whatever the user was doing — too rude for
    /// glance-at-a-number UI. So we watch for outside clicks ourselves.
    private func startDismissalWatchers() {
        // Reset first: this can be called again (open → re-import →
        // open) without an intervening close(), and overwriting a live
        // idleTimer/outsideClickMonitor without tearing down the old
        // ones first would orphan them — they'd keep running, keep
        // mutating idleElapsed alongside the new ones, and keep firing
        // for the rest of the app's lifetime.
        stopDismissalWatchers()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
        let timer = Timer(timeInterval: Self.idlePollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickIdle() }
        }
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    private func stopDismissalWatchers() {
        idleTimer?.invalidate()
        idleTimer = nil
        idleElapsed = 0
        if let m = outsideClickMonitor {
            NSEvent.removeMonitor(m)
            outsideClickMonitor = nil
        }
    }

    /// The pointer being inside the popover counts as "the user is
    /// still using this" and resets the idle clock. No separate
    /// keyboard-focus check: every control in this popover (4
    /// timeframe buttons, Refresh, Re-import) is pointer-driven and
    /// there are no text fields, so the user can't be interacting with
    /// it without the pointer being over it — pointer containment
    /// alone already covers the mid-interaction case.
    private func tickIdle() {
        guard popover.isShown, let window = popover.contentViewController?.view.window else {
            return
        }
        if window.frame.contains(NSEvent.mouseLocation) {
            idleElapsed = 0
            return
        }
        idleElapsed += Self.idlePollInterval
        if idleElapsed >= Self.autoHideAfter {
            close()
        }
    }

    private func rebuildContent() {
        guard let controller = ctx.controller else {
            popover.contentViewController = NSHostingController(
                rootView: Text("Controller not yet ready").padding())
            return
        }
        // Read the theme override fresh on every show, so changing the
        // Settings → Appearance picker takes effect on the next popover
        // open without needing app relaunch.
        // Note: `try? ctx.settings.get(.theme)` returns String?? (try?
        // wrapping String?). flatMap squashes that to String?, then ??
        // gives a concrete String for the switch.
        let themeStr = (try? ctx.settings.get(.theme)).flatMap { $0 } ?? "auto"
        let scheme: ColorScheme? = {
            switch themeStr {
            case "light": return .light
            case "dark":  return .dark
            default:      return nil  // follow system
            }
        }()
        // Closure the popover invokes when the user taps "Re-import
        // cURL…" inside an error banner. This fires from a Button
        // inside a *live, shown* popover (not before show), so it must
        // go through close() — not popover.performClose(nil) directly
        // — to tear down the idle timer and outside-click monitor too.
        // We close before opening the import window so the new window
        // isn't covered by it.
        let ctx = self.ctx
        let onReimport: () -> Void = { [weak self, weak controller] in
            self?.close()
            CURLImportWindowController.show(ctx: ctx, onSuccess: {
                Task { @MainActor in try? await controller?.pollOnce() }
            })
        }
        popover.contentViewController = NSHostingController(
            rootView: PopoverRootView(controller: controller,
                                      preferredScheme: scheme,
                                      onReimport: onReimport))
    }
}
