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

        // Placeholder content until PopoverRootView lands in Task 38.
        // This will be replaced in Task 38 — leaving the placeholder
        // path so each task's commit is self-contained.
        let placeholder = VStack {
            Text("Popover (Task 38 will fill this in)")
                .padding()
        }
        popover.contentViewController = NSHostingController(rootView: placeholder)
    }

    func toggle(from anchor: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        }
    }
}
