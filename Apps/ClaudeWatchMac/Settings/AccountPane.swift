import SwiftUI
import UsageCore

struct AccountPane: View {
    let ctx: AppContext
    @State private var email: String = "—"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("settings.account.signedInAs \(email)")
            HStack {
                Button("settings.account.signOut") {
                    try? ctx.cookieStore.clear()
                    NSApp.terminate(nil)
                }
                // "Re-login" is hidden, not removed.
                //
                // It opens LoginWindowController's WKWebView against
                // claude.ai, which is the sign-in path this app abandoned:
                // Cloudflare blocks the web view when the user agent is
                // spoofed, and Google OAuth refuses it when it isn't. The
                // cURL paste flow replaced it precisely because neither
                // branch can complete. Leaving the button visible offers
                // the user a control that cannot succeed — worse than
                // offering nothing, because failing at it looks like their
                // mistake.
                //
                // Re-authentication lives at right-click → Import from
                // cURL…, and the popover's error banners link to it
                // directly when a session expires.
                //
                // The code stays in the tree because the situation is
                // Cloudflare's, not ours: if claude.ai ever allows an
                // embedded web view again, restoring this is deleting an
                // `if false`. Delete it for real once that stops being
                // plausible.
                if false {
                    Button("settings.account.reLogin") {
                        LoginWindowController.show(ctx: ctx, onComplete: {})
                    }
                }
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
