import SwiftUI

enum Timeframe: String, CaseIterable, Identifiable {
    case oneHour = "1h"
    case eightHour = "8h"
    case dayHour = "24h"
    case oneWeek = "1w"
    var id: String { rawValue }
    var seconds: TimeInterval {
        switch self {
        case .oneHour: return 3600
        case .eightHour: return 8 * 3600
        case .dayHour: return 24 * 3600
        case .oneWeek: return 7 * 24 * 3600
        }
    }
}

struct TimeframePicker: View {
    @Binding var selection: Timeframe
    var body: some View {
        Picker("", selection: $selection) {
            ForEach(Timeframe.allCases) { t in Text(t.rawValue).tag(t) }
        }
        .pickerStyle(.segmented)
    }
}
