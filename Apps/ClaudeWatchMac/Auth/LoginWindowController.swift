import AppKit
import WebKit
import UsageCore

@MainActor
final class LoginWindowController {
    private static var currentWindow: NSWindow?

    static func show(ctx: AppContext, onComplete: @escaping () -> Void) {
        let win = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 500, height: 700),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        win.title = String(localized: "login.window.title", defaultValue: "Sign in to claude.ai")
        win.center()

        let view = LoginWebView(onSuccess: { pkg in
            try? ctx.cookieStore.save(pkg)
            DispatchQueue.main.async {
                win.close()
                currentWindow = nil
                onComplete()
            }
        })
        win.contentView = view
        win.makeKeyAndOrderFront(nil)
        currentWindow = win
    }
}
