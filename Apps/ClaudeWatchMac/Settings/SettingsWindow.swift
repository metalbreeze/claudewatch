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
                .tabItem { Label("Account", systemImage: "person") }
            AlertsPane(ctx: ctx)
                .tabItem { Label("Alerts", systemImage: "bell") }
            DataPane(ctx: ctx)
                .tabItem { Label("Data", systemImage: "tray") }
        }
        .frame(width: 420, height: 320)
        .padding(12)
        let host = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: host)
        w.title = "Claude Watch Settings"
        w.styleMask = [.titled, .closable]
        w.makeKeyAndOrderFront(nil)
        window = w
    }
}
