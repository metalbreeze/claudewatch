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
            Button("popover.footer.refresh", action: onRefresh)
                .buttonStyle(.borderless)
                .font(.system(size: 11))
        }
    }

    private var footerText: String {
        guard let t = lastPollAt else {
            return String(localized: "popover.footer.neverPolled",
                defaultValue: "Never polled")
        }
        let s = Int(Date().timeIntervalSince(t))
        if s < 60 {
            return String(localized: "popover.footer.lastPollSecondsAgo \(s)" as String.LocalizationValue)
        }
        if s < 3600 {
            return String(localized: "popover.footer.lastPollMinutesAgo \(s / 60)" as String.LocalizationValue)
        }
        return String(localized: "popover.footer.lastPollHoursAgo \(s / 3600)" as String.LocalizationValue)
    }

    private var footerColor: Color {
        guard let t = lastPollAt else { return .red }
        let s = Date().timeIntervalSince(t)
        if s < 120 { return .green }
        if s < 600 { return .orange }
        return .red
    }
}
