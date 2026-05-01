import AppKit
import SwiftUI
import UsageCore

@MainActor
final class PopoverController {
    let popover = NSPopover()
    let ctx: AppContext

    init(ctx: AppContext) {
        self.ctx = ctx
        popover.contentSize = NSSize(width: 340, height: 420)
        popover.behavior = .transient
        rebuildContent()
    }

    func toggle(from anchor: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Rebuild the SwiftUI tree on every open. Without this, the
            // segmented picker shows nothing selected and the gauge bars
            // stay empty until the first interaction inside the popover —
            // a known issue with SwiftUI inside NSPopover where the view
            // doesn't re-evaluate @ObservedObject changes while offscreen.
            rebuildContent()
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
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
        popover.contentViewController = NSHostingController(
            rootView: PopoverRootView(controller: controller, preferredScheme: scheme))
    }
}
