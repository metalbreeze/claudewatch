import SwiftUI
import UsageCore

struct AccountPane: View {
    let ctx: AppContext
    @State private var email: String = "—"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Signed in as \(email)")
            HStack {
                Button("Sign out") {
                    try? ctx.cookieStore.clear()
                    NSApp.terminate(nil)
                }
                Button("Re-login") {
                    LoginWindowController.show(ctx: ctx, onComplete: {})
                }
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
