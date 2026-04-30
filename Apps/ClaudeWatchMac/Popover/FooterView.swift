import SwiftUI

struct FooterView: View {
    let lastPollAt: Date?
    let onRefresh: () -> Void

    var body: some View {
        HStack {
            Text(footerText)
                .font(.system(size: 11))
                .foregroundStyle(footerColor)
            Spacer()
            Button("Refresh", action: onRefresh)
                .buttonStyle(.borderless)
                .font(.system(size: 11))
        }
    }

    private var footerText: String {
        guard let t = lastPollAt else { return "Never polled" }
        let s = Int(Date().timeIntervalSince(t))
        if s < 60 { return "Last poll: \(s)s ago" }
        if s < 3600 { return "Last poll: \(s/60)m ago" }
        return "Last poll: \(s/3600)h ago"
    }
    private var footerColor: Color {
        guard let t = lastPollAt else { return .red }
        let s = Date().timeIntervalSince(t)
        if s < 120 { return .green }
        if s < 600 { return .orange }
        return .red
    }
}
