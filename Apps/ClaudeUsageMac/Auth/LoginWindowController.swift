import AppKit
import UsageCore

/// STUB — Task 31 replaces this with a real WKWebView-based login flow.
/// For now, the AppDelegate calls `show(...)` whenever no Keychain cookie is
/// present, but the stub immediately invokes `onComplete()` so the polling
/// path (Task 30) can be exercised end-to-end before the real login lands.
@MainActor
enum LoginWindowController {
    static func show(ctx: AppContext, onComplete: @escaping () -> Void) {
        onComplete()
    }
}
