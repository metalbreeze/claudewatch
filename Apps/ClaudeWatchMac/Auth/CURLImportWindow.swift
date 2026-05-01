import AppKit
import SwiftUI
import UsageCore

@MainActor
enum CURLImportWindowController {
    private static var window: NSWindow?

    static func show(ctx: AppContext, onSuccess: @escaping () -> Void) {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            return
        }
        let view = CURLImportView { imp in
            do {
                try CURLImportApplier.apply(imp, ctx: ctx)
                // Show a success confirmation BEFORE closing the import
                // window. Without this, the window vanishes silently and
                // the app looks like it exited (LSUIElement = no Dock icon).
                let alert = NSAlert()
                alert.messageText = String(localized: "cURL.success.title", defaultValue: "Imported")
                alert.informativeText = String(localized: "cURL.success.body",
                    defaultValue: """
                    Endpoint and cookies saved. Polling has started.

                    Check the menu bar (top-right of your screen) for the ⌬ icon. Hover it for status:
                    • ⌬ N%   — polling succeeded
                    • ⌬ ⚠    — polling failed; tooltip shows why
                    • ⌬ —    — no data yet (first poll still running)

                    Right-click the icon for Settings or to re-import.
                    """)
                alert.alertStyle = .informational
                alert.runModal()
                window?.close()
                window = nil
                onSuccess()
            } catch {
                let alert = NSAlert()
                alert.messageText = String(localized: "cURL.failure.title", defaultValue: "Import failed")
                alert.informativeText = "\(error)"
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
        let host = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: host)
        w.title = String(localized: "cURL.window.title", defaultValue: "Import from cURL")
        w.styleMask = [.titled, .closable, .resizable]
        w.setContentSize(NSSize(width: 640, height: 540))
        w.center()
        // Float above other apps. Without this, switching to Safari/Chrome
        // hides this window behind the browser, and our LSUIElement app
        // has no Dock icon for the user to click back to. Floating means
        // the user can do DevTools work in Chrome with this window
        // visible right next to it, ready for the paste.
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }
}

private struct CURLImportView: View {
    @State private var pasted = ""
    @State private var error: String?
    let onImport: (CURLImport) -> Void

    /// Returns nil if the cURL looks like a real claude.ai usage request,
    /// otherwise a human-readable diagnostic. Catches three classes of
    /// wrong-cURL paste:
    ///
    ///   1. A request to a non-claude.ai host (e.g. Datadog telemetry)
    ///   2. A claude.ai request that isn't the usage endpoint
    ///      (e.g. /api/account)
    ///   3. A claude.ai request without a session cookie
    private func validate(_ imp: CURLImport) -> String? {
        guard let host = imp.url.host?.lowercased() else {
            return String(localized: "cURL.error.noURL",
                defaultValue: "URL has no host — paste looks malformed.")
        }
        if !host.contains("claude.ai") {
            return String(localized: "cURL.error.wrongHost \(host)" as String.LocalizationValue)
        }
        if !imp.url.path.lowercased().contains("usage") {
            return String(localized: "cURL.error.wrongPath \(imp.url.path)" as String.LocalizationValue)
        }
        if imp.cookies["sessionKey"] == nil {
            return String(localized: "cURL.error.missingSessionKey",
                defaultValue: """
                No 'sessionKey' cookie found. Make sure you copied the \
                cURL while signed in to claude.ai (DevTools → Network).
                """)
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("cURL.heading")
                .font(.title3.bold())

            VStack(alignment: .leading, spacing: 4) {
                Text("cURL.howTo.heading")
                    .font(.subheadline.weight(.semibold))
                Text("cURL.howTo.step1")
                // Use verbatim() so SwiftUI doesn't auto-link the URL —
                // clicking it would open Chrome and hide this window.
                Text(verbatim: String(localized: "cURL.howTo.urlExample",
                    defaultValue: "2. Open the URL  claude.ai/settings/usage  with DevTools open (Cmd-Option-I)."))
                Text("cURL.howTo.step3")
                Text("cURL.howTo.step4")
                Text(verbatim: "       https://claude.ai/api/organizations/{your-org-uuid}/usage")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                Text(verbatim: String(localized: "cURL.howTo.responseHint",
                    defaultValue: "   The response is small JSON with fields like \"five_hour\" and \"seven_day\"."))
                Text("cURL.howTo.step5")
                Text("cURL.howTo.step6")
                Text("cURL.howTo.windowFloats")
                    .font(.caption.italic())
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .textSelection(.disabled)

            TextEditor(text: $pasted)
                .font(.system(size: 11, design: .monospaced))
                .frame(minHeight: 260)
                .padding(6)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1))

            if let error {
                Text("⚠︎ \(error)")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("cURL.button.cancel") {
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.cancelAction)
                Button("cURL.button.import") {
                    do {
                        let parsed = try CURLParser.parse(pasted)
                        if let problem = validate(parsed) {
                            error = problem
                            return
                        }
                        error = nil
                        onImport(parsed)
                    } catch {
                        self.error = "\(error)"
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 600, minHeight: 500)
    }
}
