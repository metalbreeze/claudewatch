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
                window?.close()
                window = nil
                onSuccess()
            } catch {
                let alert = NSAlert()
                alert.messageText = "Import failed"
                alert.informativeText = "\(error)"
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
        let host = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: host)
        w.title = "Import from cURL"
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import endpoint + cookies from a real browser")
                .font(.title3.bold())

            VStack(alignment: .leading, spacing: 4) {
                Text("How to grab the cURL:")
                    .font(.subheadline.weight(.semibold))
                Text("1. In Safari or Chrome, sign in to claude.ai.")
                // Use verbatim() so SwiftUI doesn't auto-link the URL —
                // clicking it would open Chrome and hide this window.
                Text(verbatim: "2. Open the URL  claude.ai/settings/usage  with DevTools open (Cmd-Option-I).")
                Text("3. Click the Network tab, then reload the page.")
                Text(verbatim: "4. Look for the JSON request that returns usage data (probably under /api/…).")
                Text("5. Right-click that request → Copy → Copy as cURL.")
                Text("6. Paste below and click Import.")
                Text("(This window stays on top while you switch to the browser.)")
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
                Button("Cancel") {
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.cancelAction)
                Button("Import") {
                    do {
                        let parsed = try CURLParser.parse(pasted)
                        if parsed.cookies["sessionKey"] == nil {
                            error = "No 'sessionKey' cookie found in the cURL — make sure the request was made while signed in to claude.ai."
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
