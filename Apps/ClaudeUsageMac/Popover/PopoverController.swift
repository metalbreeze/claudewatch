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
        guard let controller = ctx.controller else {
            popover.contentViewController = NSHostingController(
                rootView: Text("Controller not yet ready").padding())
            return
        }
        popover.contentViewController = NSHostingController(
            rootView: PopoverRootView(controller: controller))
    }

    func toggle(from anchor: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        }
    }
}
