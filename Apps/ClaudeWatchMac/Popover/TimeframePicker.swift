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

/// Pure-SwiftUI segmented picker. macOS's `Picker(.segmented)` is backed
/// by NSSegmentedControl which doesn't paint its selected segment inside
/// an NSPopover until first interaction (a SwiftUI/AppKit bridge quirk).
/// Drawing it ourselves gives us a correct first render.
struct TimeframePicker: View {
    @Binding var selection: Timeframe

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Timeframe.allCases) { t in
                Button {
                    selection = t
                } label: {
                    Text(t.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(t == selection ? Color.white : Color.primary)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(t == selection
                                      ? Color.accentColor
                                      : Color.secondary.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
