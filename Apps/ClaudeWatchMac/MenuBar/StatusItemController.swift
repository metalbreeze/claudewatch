import AppKit

/// Owns the `NSStatusItem` in the macOS menu bar and renders the at-a-glance
/// label (e.g. `⌬ 47%`). Left-click delegates to `onClick` (popover);
/// right-click shows a context menu with Settings and Quit.
final class StatusItemController {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    /// Called when the user left-clicks the menu bar icon.
    var onClick: (() -> Void)?

    /// Called when the user chooses "Settings…" from the right-click menu.
    var onSettings: (() -> Void)?

    /// Called when the user chooses "Import from cURL…" from the right-click menu.
    var onImportCURL: (() -> Void)?

    init() {
        if let button = item.button {
            button.title = "⌬ ⏳"
            button.toolTip = String(localized: "status.tooltip.initializing",
                defaultValue: "Claude Watch — initializing")
            button.target = self
            button.action = #selector(buttonClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func buttonClicked() {
        // Distinguish left from right click via the current event.
        if let event = NSApp.currentEvent {
            switch event.type {
            case .rightMouseUp:
                showRightClickMenu()
            default:
                onClick?()
            }
        } else {
            onClick?()
        }
    }

    private func showRightClickMenu() {
        let menu = NSMenu()
        let importItem = NSMenuItem(
            title: String(localized: "menu.importFromCURL", defaultValue: "Import from cURL…"),
            action: #selector(triggerImportCURL),
            keyEquivalent: "i")
        importItem.target = self
        menu.addItem(importItem)
        menu.addItem(.separator())
        let settings = NSMenuItem(
            title: String(localized: "menu.settings", defaultValue: "Settings…"),
            action: #selector(triggerSettings),
            keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: String(localized: "menu.quit", defaultValue: "Quit Claude Watch"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"))
        // Show, then immediately remove so it doesn't stay attached.
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func triggerSettings() {
        onSettings?()
    }

    @objc private func triggerImportCURL() {
        onImportCURL?()
    }

    /// Update the menu bar text and tooltip together so they never drift.
    func setText(_ s: String, tooltip: String) {
        item.button?.title = s
        item.button?.toolTip = tooltip
    }
}
