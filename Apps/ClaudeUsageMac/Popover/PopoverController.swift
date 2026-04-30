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
        popover.contentViewController = NSHostingController(
            rootView: PopoverRootView(controller: controller))
    }
}
