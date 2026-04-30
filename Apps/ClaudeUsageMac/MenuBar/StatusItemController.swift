import AppKit

/// Owns the `NSStatusItem` in the macOS menu bar and renders the at-a-glance
/// label (e.g. `⌬ 47%`). Click handling is delegated via `onClick`.
final class StatusItemController {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    /// Called when the user clicks the menu bar icon (left or right).
    /// AppDelegate wires this to popover toggling once the popover ships
    /// (Task 34).
    var onClick: (() -> Void)?

    init() {
        if let button = item.button {
            button.title = "⌬ ⏳"
            button.toolTip = "Claude Usage — initializing"
            button.target = self
            button.action = #selector(buttonClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func buttonClicked() {
        onClick?()
    }

    /// Update the menu bar text and tooltip together so they never drift.
    func setText(_ s: String, tooltip: String) {
        item.button?.title = s
        item.button?.toolTip = tooltip
    }
}
