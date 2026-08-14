import AppKit
import SwiftUI
import UsageCore

@MainActor
final class PopoverController {
    let popover = NSPopover()
    let ctx: AppContext

    /// Seconds the pointer must stay outside the popover (with the
    /// popover also not holding keyboard focus) before it closes.
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
    /// popover, no matter which of the three dismissal triggers fired.
    func close() {
        stopDismissalWatchers()
        popover.performClose(nil)
    }

    /// `.transient` alone doesn't dismiss this popover: in an
    /// LSUIElement process, clicking the status item doesn't activate
    /// the app, so the outside-click event that `.transient` waits for
    /// never arrives. Calling NSApp.activate would fix that but steals
    /// keyboard focus from whatever the user was doing — too rude for
    /// glance-at-a-number UI. So we watch for outside clicks ourselves.
    private func startDismissalWatchers() {
        idleElapsed = 0
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

    /// The pointer being inside the popover, or the popover holding
    /// keyboard focus, both count as "the user is still using this".
    /// The focus clause matters because clicking a control inside the
    /// popover activates the app — without it, a user who clicked a
    /// timeframe button and then moved the mouse off would get the
    /// popover yanked mid-interaction.
    private func tickIdle() {
        guard popover.isShown, let window = popover.contentViewController?.view.window else {
            return
        }
        let pointerInside = window.frame.contains(NSEvent.mouseLocation)
        if pointerInside || window.isKeyWindow {
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
        // cURL…" inside an error banner. We close the popover before
        // opening the import window so the new window isn't covered
        // by it (the popover is .transient and would dismiss itself
        // on focus loss anyway, but explicit is clearer).
        let ctx = self.ctx
        let popover = self.popover
        let onReimport: () -> Void = { [weak controller] in
            popover.performClose(nil)
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
