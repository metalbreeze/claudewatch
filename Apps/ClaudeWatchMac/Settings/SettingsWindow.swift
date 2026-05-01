import AppKit
import SwiftUI
import UsageCore

@MainActor
enum SettingsWindowController {
    private static var window: NSWindow?

    static func show(ctx: AppContext) {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            return
        }
        let view = TabView {
            AccountPane(ctx: ctx)
                .tabItem { Label("settings.tab.account", systemImage: "person") }
            AlertsPane(ctx: ctx)
                .tabItem { Label("settings.tab.alerts", systemImage: "bell") }
            DataPane(ctx: ctx)
                .tabItem { Label("settings.tab.data", systemImage: "tray") }
        }
        .frame(width: 420, height: 320)
        .padding(12)
        let host = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: host)
        w.title = String(localized: "settings.window.title", defaultValue: "Claude Watch Settings")
        w.styleMask = [.titled, .closable]
        w.makeKeyAndOrderFront(nil)
        window = w
    }
}
