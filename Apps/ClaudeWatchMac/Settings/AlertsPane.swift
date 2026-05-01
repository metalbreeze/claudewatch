import SwiftUI
import UsageCore

struct AlertsPane: View {
    let ctx: AppContext
    @State private var enabled: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(AlertKind.allCases, id: \.self) { k in
                Toggle(label(k), isOn: Binding(
                    get: { enabled.contains(k.rawValue) },
                    set: { v in
                        if v { enabled.insert(k.rawValue) } else { enabled.remove(k.rawValue) }
                        try? ctx.settings.set(.alertThresholds, enabled.joined(separator: ","))
                    }))
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            let raw = (try? ctx.settings.get(.alertThresholds))
                ?? AlertKind.allCases.map(\.rawValue).joined(separator: ",")
            enabled = Set((raw ?? "").split(separator: ",").map(String.init))
        }
    }

    private func label(_ k: AlertKind) -> String {
        switch k {
        case .fiveHourForecast:
            return String(localized: "settings.alerts.fiveHourForecast",
                defaultValue: "Warn before hitting 5h limit")
        case .fiveHourHit:
            return String(localized: "settings.alerts.fiveHourHit",
                defaultValue: "Notify when 5h limit reached")
        case .weekNinety:
            return String(localized: "settings.alerts.weekNinety",
                defaultValue: "Notify at 90% of weekly limit")
        case .weekHundred:
            return String(localized: "settings.alerts.weekHundred",
                defaultValue: "Notify when weekly limit reached")
        case .authExpired:
            return String(localized: "settings.alerts.authExpired",
                defaultValue: "Notify when login expires")
        case .scrapeBroken:
            return String(localized: "settings.alerts.scrapeBroken",
                defaultValue: "Notify when source format changes")
        }
    }
}
