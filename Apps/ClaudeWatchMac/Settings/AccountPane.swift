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
                Button("settings.account.reLogin") {
                    LoginWindowController.show(ctx: ctx, onComplete: {})
                }
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
