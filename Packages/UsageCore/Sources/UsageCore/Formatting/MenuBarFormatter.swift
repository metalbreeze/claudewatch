import Foundation

/// Which of the three quota percentages the menu bar shows, and whether
/// each carries a short label.
public struct MenuBarDisplayOptions: Equatable {
    public var show5h: Bool
    public var showWeek: Bool
    public var showFable: Bool
    public var showLabels: Bool

    public init(show5h: Bool, showWeek: Bool, showFable: Bool, showLabels: Bool) {
        self.show5h = show5h
        self.showWeek = showWeek
        self.showFable = showFable
        self.showLabels = showLabels
    }

    /// Ships showing 5h and Fable with labels, weekly off.
    ///
    /// Fable is on by default on purpose: this app exists to surface the
    /// quota that is actually blocking you, and Fable is frequently that
    /// quota while 5h reads comfortable. A 5h-only default would leave
    /// anyone who never opens Settings with the same blind spot the
    /// feature was built to remove. Weekly is off because it moves the
    /// slowest and costs the most width for the least information.
    public static let `default` = MenuBarDisplayOptions(
        show5h: true, showWeek: false, showFable: true, showLabels: true)
}

/// Builds the menu bar's percentage string.
///
/// Lives in UsageCore rather than beside `AppDelegate` so it can be
/// unit-tested — the macOS app target isn't reachable from
/// `UsageCoreTests`, and this is the only part of the menu bar work
/// with branching worth asserting.
public enum MenuBarFormatter {
    /// Returns only the joined segments — no "⌬" glyph, no leading
    /// space. Composing the final title is the app's job, because the
    /// glyph is a presentation choice that doesn't belong in a
    /// platform-agnostic package.
    ///
    /// Returns "" when `snapshot` is nil, when no segment is enabled,
    /// or when every enabled segment is unavailable. The nil-snapshot
    /// case exists only to make the function total: the app still
    /// renders its own "no data yet" indicator before reaching here.
    public static func segments(snapshot: UsageSnapshot?,
                                options: MenuBarDisplayOptions) -> String {
        guard let s = snapshot else { return "" }

        // Order is fixed 5h → 1w → F regardless of which are enabled,
        // so the reading position of a given number never moves when
        // the user toggles a neighbour off.
        var parts: [String] = []
        if options.show5h {
            parts.append(format(label: "5h", fraction: s.fraction5h, options: options))
        }
        if options.showWeek {
            parts.append(format(label: "1w", fraction: s.fractionWeek, options: options))
        }
        // A nil fractionFable means the account has no Fable quota at
        // all — drop the segment rather than rendering "F:0%", which
        // would claim the opposite of what's true.
        if options.showFable, let fable = s.fractionFable {
            parts.append(format(label: "F", fraction: fable, options: options))
        }
        return parts.joined(separator: "/")
    }

    private static func format(label: String,
                               fraction: Double,
                               options: MenuBarDisplayOptions) -> String {
        let pct = Int(fraction * 100)
        return options.showLabels ? "\(label):\(pct)%" : "\(pct)%"
    }
}
