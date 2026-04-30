import SwiftUI
import UsageCore

@main
struct ClaudeWatchMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        // LSUIElement = YES means we don't want a real WindowGroup.
        // The Settings scene is suppressed; menu-bar UI is provided by the
        // AppDelegate's StatusItemController.
        Settings { EmptyView() }
    }
}
