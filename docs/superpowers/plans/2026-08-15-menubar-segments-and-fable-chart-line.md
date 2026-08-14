# Configurable Menu Bar Segments + Fable Chart Line Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the menu bar show any combination of the 5h / weekly / Fable percentages with optional labels, and plot Fable on the 1-week chart.

**Architecture:** The string-assembly logic moves out of `AppDelegate` into a pure `MenuBarFormatter` inside the `UsageCore` package, where it can be unit-tested. Four boolean settings drive it, persisted through `SettingsRepository` with new typed `getBool`/`setBool` helpers. `AppearancePane` posts a notification on change so the menu bar redraws immediately instead of waiting up to 90 s for the next poll. The chart change is a single additional `LineMark` gated on the same condition as the existing weekly line.

**Tech Stack:** Swift 5.10, SwiftUI, AppKit (`NSStatusItem`, `NotificationCenter`), Swift Charts, GRDB.swift (SQLite), XCTest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-08-15-menubar-segments-and-fable-chart-line-design.md`

## Global Constraints

- **`project.yml` is the source of truth for the Xcode project.** Never edit `ClaudeWatch.xcodeproj` directly. After adding or removing any file under `Apps/`, run `xcodegen generate`. Adding files under `Packages/UsageCore/Sources/` needs no regeneration — SwiftPM globs them.
- **Menu bar segment order is always 5h → 1w → F**, regardless of which are enabled.
- **Segments join with `/`.** Labels, when enabled, are `5h`, `1w`, `F`, each followed by `:` with no spaces: `5h:26%/1w:69%/F:99%`.
- **A `nil` Fable value drops its segment entirely** — never `F:0%`, never a doubled or trailing `/`.
- **The existing `⌬ —` no-data state must survive.** It means "the first poll hasn't returned"; `⌬` alone means "the user selected nothing". Collapsing them loses a real signal on first launch.
- **Percentages are `Int(fraction * 100)`** — the same rounding `render()` uses today.
- **All 8 locales stay in sync:** `en`, `zh-Hans`, `zh-Hant`, `ja`, `ko`, `es`, `de`, `fr`. A key added to one must exist in all 8, with matching format-specifier count and type.
- Swift package tests: `cd Packages/UsageCore && swift test`. macOS app build: `xcodebuild -project ClaudeWatch.xcodeproj -scheme ClaudeWatchMac -configuration Debug -destination 'platform=macOS' build`.
- Working directory: `/Users/shu/workspace/myportfolio/claude.usage`. Branch: `main` — the user works this project directly on main; do not create a branch.
- **Heredoc-style `git commit -m "$(cat <<'EOF' …)"` has failed repeatedly in this shell.** Write the message to a scratch file and use `git commit -F`.

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `Packages/UsageCore/Sources/UsageCore/Formatting/MenuBarFormatter.swift` | `MenuBarDisplayOptions` + the pure `segments(snapshot:options:)` function | 1 |
| `Packages/UsageCore/Tests/UsageCoreTests/Formatting/MenuBarFormatterTests.swift` | 7 formatter cases | 1 |
| `Packages/UsageCore/Sources/UsageCore/Storage/SettingsRepository.swift` | 4 new `Key` cases + `getBool`/`setBool` | 2 |
| `Packages/UsageCore/Tests/UsageCoreTests/Storage/SettingsRepositoryTests.swift` | 2 bool round-trip cases | 2 |
| `Apps/ClaudeWatchMac/AppDelegate.swift` | `render()` reads settings and uses the formatter; observes the refresh notification; 3-value tooltip | 3 |
| `Apps/ClaudeWatchMac/Settings/AppearancePane.swift` | 4 checkboxes + notification post | 3 |
| `Apps/ClaudeWatchMac/Popover/LineChartView.swift` | Fable `LineMark`; corrected `ChartPalette.actualFable` doc comment | 4 |
| `Apps/ClaudeWatchMac/Resources/*.lproj/Localizable.strings` × 8 | 6 new strings | 3 |

Tasks 1–2 are package-only and independent of each other. Task 3 consumes both and is where the feature becomes visible. Task 4 is independent of 1–3 and could be done at any point.

---

## Task 1: `MenuBarFormatter` in UsageCore

**Files:**
- Create: `Packages/UsageCore/Sources/UsageCore/Formatting/MenuBarFormatter.swift`
- Create: `Packages/UsageCore/Tests/UsageCoreTests/Formatting/MenuBarFormatterTests.swift`

**Interfaces:**
- Consumes: `UsageSnapshot.fraction5h: Double`, `.fractionWeek: Double`, `.fractionFable: Double?` — all already exist.
- Produces:
  - `MenuBarDisplayOptions` — a public `Equatable` struct with `show5h`, `showWeek`, `showFable`, `showLabels` (all `Bool`), a memberwise `init`, and `static let default` = `(true, false, true, true)`.
  - `MenuBarFormatter.segments(snapshot: UsageSnapshot?, options: MenuBarDisplayOptions) -> String` — returns only the joined segments, no glyph and no leading space; `""` when nothing renders.

- [ ] **Step 1: Write the failing tests**

Create `Packages/UsageCore/Tests/UsageCoreTests/Formatting/MenuBarFormatterTests.swift`:

```swift
import XCTest
@testable import UsageCore

final class MenuBarFormatterTests: XCTestCase {
    /// 26% / 69% / 99% on the 0–10000 scale the scrapers use.
    private func snap(fable: Int? = 9900) -> UsageSnapshot {
        let t = Date(timeIntervalSince1970: 1_770_000_000)
        return UsageSnapshot(
            timestamp: t, plan: .pro,
            used5h: 2600, ceiling5h: 10_000, resetTime5h: t.addingTimeInterval(3600),
            usedWeek: 6900, ceilingWeek: 10_000, resetTimeWeek: t.addingTimeInterval(86_400),
            sourceVersion: "test", raw: Data(),
            usedFable: fable,
            resetTimeFable: fable == nil ? nil : t.addingTimeInterval(86_400),
            fableIsActive: fable != nil)
    }

    private func opts(_ five: Bool, _ week: Bool, _ fable: Bool, _ labels: Bool)
        -> MenuBarDisplayOptions {
        MenuBarDisplayOptions(show5h: five, showWeek: week,
                              showFable: fable, showLabels: labels)
    }

    func test_allThreeWithLabels() {
        let s = MenuBarFormatter.segments(snapshot: snap(),
                                          options: opts(true, true, true, true))
        XCTAssertEqual(s, "5h:26%/1w:69%/F:99%")
    }

    func test_allThreeWithoutLabels() {
        let s = MenuBarFormatter.segments(snapshot: snap(),
                                          options: opts(true, true, true, false))
        XCTAssertEqual(s, "26%/69%/99%")
    }

    func test_fableAbsent_dropsSegmentEntirely() {
        // No trailing slash, no "F:0%" — the account simply has no
        // Fable quota, which is not the same as having used none of it.
        let s = MenuBarFormatter.segments(snapshot: snap(fable: nil),
                                          options: opts(true, true, true, true))
        XCTAssertEqual(s, "5h:26%/1w:69%")
    }

    func test_nothingSelected_returnsEmpty() {
        let s = MenuBarFormatter.segments(snapshot: snap(),
                                          options: opts(false, false, false, false))
        XCTAssertEqual(s, "")
    }

    func test_nilSnapshot_returnsEmpty() {
        let s = MenuBarFormatter.segments(snapshot: nil,
                                          options: opts(true, true, true, true))
        XCTAssertEqual(s, "")
    }

    func test_singleSegmentNoLabel_hasNoStraySeparator() {
        let s = MenuBarFormatter.segments(snapshot: snap(),
                                          options: opts(true, false, false, false))
        XCTAssertEqual(s, "26%")
    }

    func test_orderIsFixedRegardlessOfSelection() {
        // 5h is skipped, but 1w must still precede F.
        let s = MenuBarFormatter.segments(snapshot: snap(),
                                          options: opts(false, true, true, true))
        XCTAssertEqual(s, "1w:69%/F:99%")
    }

    func test_defaultOptions() {
        // Documented default: 5h + Fable + labels, weekly off.
        let d = MenuBarDisplayOptions.default
        XCTAssertTrue(d.show5h)
        XCTAssertFalse(d.showWeek)
        XCTAssertTrue(d.showFable)
        XCTAssertTrue(d.showLabels)
        XCTAssertEqual(MenuBarFormatter.segments(snapshot: snap(), options: d),
                       "5h:26%/F:99%")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd Packages/UsageCore && swift test --filter MenuBarFormatterTests 2>&1 | tail -20
```

Expected: FAIL — `cannot find 'MenuBarFormatter' in scope` (and the same for `MenuBarDisplayOptions`).

- [ ] **Step 3: Write the implementation**

Create `Packages/UsageCore/Sources/UsageCore/Formatting/MenuBarFormatter.swift`:

```swift
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
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd Packages/UsageCore && swift test --filter MenuBarFormatterTests 2>&1 | tail -10
```

Expected: PASS, 8 tests.

- [ ] **Step 5: Run the full package suite**

```bash
cd Packages/UsageCore && swift test 2>&1 | tail -6
```

Expected: `Executed N tests, with 0 failures`, N = previous count + 8.

- [ ] **Step 6: Commit**

Write the message to `/tmp/t1.txt`:

```
feat(core): add MenuBarFormatter for configurable menu bar segments

Pure string assembly for the menu bar's percentage display, extracted
into UsageCore so it can be unit-tested — the macOS app target isn't
reachable from UsageCoreTests, and the branching (which segments, with
or without labels, Fable present or not) is the only part of the menu
bar work worth asserting.

Segment order is fixed 5h -> 1w -> F regardless of which are enabled,
so a given number's reading position never shifts when the user
toggles a neighbour off.

A nil fractionFable drops the segment entirely rather than rendering
"F:0%" — the account has no Fable quota, which is the opposite of
having used none of it.

Default is 5h + Fable + labels, weekly off. Fable defaults on because
this app exists to surface the quota that is actually blocking you,
and a 5h-only default reproduces the blind spot for anyone who never
opens Settings.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
```

```bash
git add Packages/UsageCore/Sources/UsageCore/Formatting/MenuBarFormatter.swift \
        Packages/UsageCore/Tests/UsageCoreTests/Formatting/MenuBarFormatterTests.swift
git commit -F /tmp/t1.txt
```

---

## Task 2: Boolean settings support

**Files:**
- Modify: `Packages/UsageCore/Sources/UsageCore/Storage/SettingsRepository.swift`
- Test: `Packages/UsageCore/Tests/UsageCoreTests/Storage/SettingsRepositoryTests.swift`

**Interfaces:**
- Consumes: nothing from Task 1 — the two package tasks are independent.
- Produces:
  - Four new `SettingsRepository.Key` cases: `menuBarShow5h`, `menuBarShowWeek`, `menuBarShowFable`, `menuBarShowLabels`.
  - `func getBool(_ key: Key, default def: Bool) throws -> Bool`
  - `func setBool(_ key: Key, _ value: Bool) throws`

- [ ] **Step 1: Write the failing tests**

Append these two methods inside the existing `final class SettingsRepositoryTests: XCTestCase { ... }` in `Packages/UsageCore/Tests/UsageCoreTests/Storage/SettingsRepositoryTests.swift`, before the closing brace. The existing tests create their own `DatabaseQueue()` per test; follow that pattern.

```swift
    func test_getBool_absentKey_returnsDefault() throws {
        let dbq = try DatabaseQueue()
        try Database.migrator.migrate(dbq)
        let repo = SettingsRepository(dbq: dbq)
        XCTAssertTrue(try repo.getBool(.menuBarShowFable, default: true))
        XCTAssertFalse(try repo.getBool(.menuBarShowWeek, default: false))
    }

    func test_setBoolThenGetBool_roundTrips() throws {
        let dbq = try DatabaseQueue()
        try Database.migrator.migrate(dbq)
        let repo = SettingsRepository(dbq: dbq)

        // Writing false must read back false even when the default is
        // true — this is the case a naive "any stored string is true"
        // parse would get wrong.
        try repo.setBool(.menuBarShow5h, false)
        XCTAssertFalse(try repo.getBool(.menuBarShow5h, default: true))

        try repo.setBool(.menuBarShow5h, true)
        XCTAssertTrue(try repo.getBool(.menuBarShow5h, default: false))
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd Packages/UsageCore && swift test --filter SettingsRepositoryTests 2>&1 | tail -20
```

Expected: FAIL — `type 'SettingsRepository.Key' has no member 'menuBarShowFable'` and `value of type 'SettingsRepository' has no member 'getBool'`.

- [ ] **Step 3: Add the keys and the typed helpers**

In `Packages/UsageCore/Sources/UsageCore/Storage/SettingsRepository.swift`, add four cases to the end of the `Key` enum, after `case endpointConfig`:

```swift
        case menuBarShow5h            // "1"|"0" — see getBool/setBool
        case menuBarShowWeek          // "1"|"0"
        case menuBarShowFable         // "1"|"0"
        case menuBarShowLabels        // "1"|"0"
```

Then add the two helpers after the existing `set(_:_:)` method, inside the struct:

```swift
    /// Booleans are stored as "1"/"0". A typed accessor keeps that
    /// encoding in one place and gives every caller a non-optional
    /// answer — the raw `get` returns String? and each menu bar
    /// setting needs its own default when unset.
    ///
    /// Anything other than exactly "1" or "0" (a hand-edited database,
    /// a value written by a future version) falls back to `def` rather
    /// than being coerced, so a malformed row can't silently flip a
    /// setting to true.
    public func getBool(_ key: Key, default def: Bool) throws -> Bool {
        switch try get(key) {
        case "1": return true
        case "0": return false
        default:  return def
        }
    }

    public func setBool(_ key: Key, _ value: Bool) throws {
        try set(key, value ? "1" : "0")
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd Packages/UsageCore && swift test --filter SettingsRepositoryTests 2>&1 | tail -10
```

Expected: PASS.

- [ ] **Step 5: Run the full package suite**

```bash
cd Packages/UsageCore && swift test 2>&1 | tail -6
```

Expected: `Executed N tests, with 0 failures`.

- [ ] **Step 6: Commit**

Write the message to `/tmp/t2.txt`:

```
feat(core): add boolean settings support for menu bar segments

Four new keys (menuBarShow5h / Week / Fable / Labels) plus typed
getBool/setBool helpers.

The raw accessors return String?, and every one of these settings
needs its own non-nil default when unset, so parsing at each call site
would have meant repeating the "1"/"0" encoding four times in the
settings pane and again in the app delegate.

getBool falls back to the caller's default on anything that isn't
exactly "1" or "0" rather than coercing. A hand-edited database or a
value written by a future version can't silently flip a setting on.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
```

```bash
git add Packages/UsageCore/Sources/UsageCore/Storage/SettingsRepository.swift \
        Packages/UsageCore/Tests/UsageCoreTests/Storage/SettingsRepositoryTests.swift
git commit -F /tmp/t2.txt
```

---

## Task 3: Wire the menu bar and the settings checkboxes

**Files:**
- Modify: `Apps/ClaudeWatchMac/AppDelegate.swift`
- Modify: `Apps/ClaudeWatchMac/Settings/AppearancePane.swift`
- Modify: `Apps/ClaudeWatchMac/Resources/{en,zh-Hans,zh-Hant,ja,ko,es,de,fr}.lproj/Localizable.strings`

**Interfaces:**
- Consumes:
  - `MenuBarFormatter.segments(snapshot: UsageSnapshot?, options: MenuBarDisplayOptions) -> String` (Task 1)
  - `MenuBarDisplayOptions(show5h:showWeek:showFable:showLabels:)` and `.default` (Task 1)
  - `SettingsRepository.getBool(_:default:)` / `.setBool(_:_:)` and the four `menuBarShow*` keys (Task 2)
- Produces: `Notification.Name.menuBarDisplayOptionsChanged`, posted by the settings pane and observed by `AppDelegate`.

- [ ] **Step 1: Add the notification name and the options reader to AppDelegate**

In `Apps/ClaudeWatchMac/AppDelegate.swift`, add this extension at the very bottom of the file, after the existing `NotificationSinkAdapter` struct:

```swift
extension Notification.Name {
    /// Posted by AppearancePane after any menu bar checkbox changes.
    ///
    /// Without it the menu bar would only pick up a new setting on the
    /// next poll — up to 90 seconds of staring at a checkbox that
    /// appears to do nothing.
    static let menuBarDisplayOptionsChanged = Notification.Name("menuBarDisplayOptionsChanged")
}
```

- [ ] **Step 2: Replace `render()` and add the observer**

In `Apps/ClaudeWatchMac/AppDelegate.swift`, replace the whole `render()` method:

```swift
    private func render() {
        guard let snap = ctx.controller?.state.latest else {
            // Distinct from "⌬" with no digits, which means the user
            // switched every segment off. This one means the first poll
            // hasn't come back yet.
            statusItem.setText("⌬ —", tooltip: String(localized: "status.tooltip.noData",
                defaultValue: "No data"))
            return
        }
        let segments = MenuBarFormatter.segments(snapshot: snap, options: menuBarOptions())
        let title = segments.isEmpty ? "⌬" : "⌬ \(segments)"

        // The tooltip always carries all three values, whatever the
        // menu bar is set to show: the bar is what the user chose to
        // watch, the tooltip is the full picture.
        let pct = Int(snap.fraction5h * 100)
        let weekPct = Int(snap.fractionWeek * 100)
        let tooltip: String
        if let fable = snap.fractionFable {
            let fablePct = Int(fable * 100)
            tooltip = String(localized:
                "status.tooltip.usageWithFable \(pct) \(weekPct) \(fablePct)"
                as String.LocalizationValue)
        } else {
            tooltip = String(localized:
                "status.tooltip.usage \(pct) \(weekPct)" as String.LocalizationValue)
        }
        statusItem.setText(title, tooltip: tooltip)
    }

    /// Reads the four persisted menu bar checkboxes. Falls back to
    /// `MenuBarDisplayOptions.default` field by field, so a database
    /// that predates these keys still renders sensibly.
    private func menuBarOptions() -> MenuBarDisplayOptions {
        let d = MenuBarDisplayOptions.default
        return MenuBarDisplayOptions(
            show5h:     (try? ctx.settings.getBool(.menuBarShow5h,     default: d.show5h))     ?? d.show5h,
            showWeek:   (try? ctx.settings.getBool(.menuBarShowWeek,   default: d.showWeek))   ?? d.showWeek,
            showFable:  (try? ctx.settings.getBool(.menuBarShowFable,  default: d.showFable))  ?? d.showFable,
            showLabels: (try? ctx.settings.getBool(.menuBarShowLabels, default: d.showLabels)) ?? d.showLabels)
    }
```

Then register the observer. In `applicationDidFinishLaunching`, immediately after the line `popover = PopoverController(ctx: ctx)`, insert:

```swift
            NotificationCenter.default.addObserver(
                forName: .menuBarDisplayOptionsChanged, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.render() }
            }
```

- [ ] **Step 3: Add the checkboxes to AppearancePane**

In `Apps/ClaudeWatchMac/Settings/AppearancePane.swift`, replace the entire file:

```swift
import SwiftUI
import UsageCore

/// Two groups of appearance settings.
///
/// **Theme** overrides the popover's color scheme independently of the
/// system-wide macOS setting. Persisted under SettingsRepository.theme
/// and read back by PopoverController on every popover open, so changes
/// take effect the next time the user clicks the menu bar icon.
///
/// **Menu bar** picks which of the three quota percentages appear in the
/// status item and whether they carry short labels. Each toggle posts
/// `.menuBarDisplayOptionsChanged` so the bar redraws immediately —
/// waiting for the next 90 s poll would make the checkbox look broken.
struct AppearancePane: View {
    let ctx: AppContext
    @State private var theme: String = "auto"
    @State private var show5h = true
    @State private var showWeek = false
    @State private var showFable = true
    @State private var showLabels = true
    /// False when the account has no Fable quota. The checkbox is
    /// disabled rather than hidden: a user on a plan without Fable
    /// should be able to see that the option exists.
    @State private var fableAvailable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("settings.appearance.theme")
                .font(.subheadline.weight(.semibold))
            Picker("", selection: $theme) {
                Text("settings.appearance.themeAuto").tag("auto")
                Text("settings.appearance.themeLight").tag("light")
                Text("settings.appearance.themeDark").tag("dark")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: theme) { newValue in
                try? ctx.settings.set(.theme, newValue)
            }
            Text("settings.appearance.themeNote")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Divider()

            Text("settings.appearance.menuBarSection")
                .font(.subheadline.weight(.semibold))
            Toggle("settings.appearance.menuBarShow5h", isOn: $show5h)
                .onChange(of: show5h) { v in write(.menuBarShow5h, v) }
            Toggle("settings.appearance.menuBarShowWeek", isOn: $showWeek)
                .onChange(of: showWeek) { v in write(.menuBarShowWeek, v) }
            Toggle("settings.appearance.menuBarShowFable", isOn: $showFable)
                .disabled(!fableAvailable)
                .onChange(of: showFable) { v in write(.menuBarShowFable, v) }
            Toggle("settings.appearance.menuBarShowLabels", isOn: $showLabels)
                .onChange(of: showLabels) { v in write(.menuBarShowLabels, v) }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { load() }
    }

    private func load() {
        let d = MenuBarDisplayOptions.default
        theme = (try? ctx.settings.get(.theme)).flatMap { $0 } ?? "auto"
        show5h     = (try? ctx.settings.getBool(.menuBarShow5h,     default: d.show5h))     ?? d.show5h
        showWeek   = (try? ctx.settings.getBool(.menuBarShowWeek,   default: d.showWeek))   ?? d.showWeek
        showFable  = (try? ctx.settings.getBool(.menuBarShowFable,  default: d.showFable))  ?? d.showFable
        showLabels = (try? ctx.settings.getBool(.menuBarShowLabels, default: d.showLabels)) ?? d.showLabels
        fableAvailable = ctx.controller?.state.latest?.fractionFable != nil
    }

    private func write(_ key: SettingsRepository.Key, _ value: Bool) {
        try? ctx.settings.setBool(key, value)
        NotificationCenter.default.post(name: .menuBarDisplayOptionsChanged, object: nil)
    }
}
```

- [ ] **Step 4: Add the six strings to all 8 locales**

Add the five `settings.appearance.menuBar*` lines directly after the existing `"settings.appearance.themeNote"` line, and the `status.tooltip.usageWithFable` line directly after the existing `"status.tooltip.usage %lld %lld"` line, in each file.

`en.lproj`:

```
"settings.appearance.menuBarSection" = "Menu bar";
"settings.appearance.menuBarShow5h" = "Show 5-hour usage";
"settings.appearance.menuBarShowWeek" = "Show weekly usage";
"settings.appearance.menuBarShowFable" = "Show Fable usage";
"settings.appearance.menuBarShowLabels" = "Show labels (5h / 1w / F)";
```
```
"status.tooltip.usageWithFable %lld %lld %lld" = "5h: %lld%% • Week: %lld%% • Fable: %lld%%";
```

`zh-Hans.lproj`:

```
"settings.appearance.menuBarSection" = "菜单栏";
"settings.appearance.menuBarShow5h" = "显示 5 小时用量";
"settings.appearance.menuBarShowWeek" = "显示每周用量";
"settings.appearance.menuBarShowFable" = "显示 Fable 用量";
"settings.appearance.menuBarShowLabels" = "显示名称（5h / 1w / F）";
```
```
"status.tooltip.usageWithFable %lld %lld %lld" = "5小时：%lld%% • 本周：%lld%% • Fable：%lld%%";
```

`zh-Hant.lproj`:

```
"settings.appearance.menuBarSection" = "選單列";
"settings.appearance.menuBarShow5h" = "顯示 5 小時用量";
"settings.appearance.menuBarShowWeek" = "顯示每週用量";
"settings.appearance.menuBarShowFable" = "顯示 Fable 用量";
"settings.appearance.menuBarShowLabels" = "顯示名稱（5h / 1w / F）";
```
```
"status.tooltip.usageWithFable %lld %lld %lld" = "5小時：%lld%% • 本週：%lld%% • Fable：%lld%%";
```

`ja.lproj`:

```
"settings.appearance.menuBarSection" = "メニューバー";
"settings.appearance.menuBarShow5h" = "5時間の使用量を表示";
"settings.appearance.menuBarShowWeek" = "週間の使用量を表示";
"settings.appearance.menuBarShowFable" = "Fable の使用量を表示";
"settings.appearance.menuBarShowLabels" = "ラベルを表示（5h / 1w / F）";
```
```
"status.tooltip.usageWithFable %lld %lld %lld" = "5時間：%lld%% • 週間：%lld%% • Fable：%lld%%";
```

`ko.lproj`:

```
"settings.appearance.menuBarSection" = "메뉴 막대";
"settings.appearance.menuBarShow5h" = "5시간 사용량 표시";
"settings.appearance.menuBarShowWeek" = "주간 사용량 표시";
"settings.appearance.menuBarShowFable" = "Fable 사용량 표시";
"settings.appearance.menuBarShowLabels" = "레이블 표시 (5h / 1w / F)";
```
```
"status.tooltip.usageWithFable %lld %lld %lld" = "5시간: %lld%% • 주간: %lld%% • Fable: %lld%%";
```

`es.lproj`:

```
"settings.appearance.menuBarSection" = "Barra de menús";
"settings.appearance.menuBarShow5h" = "Mostrar uso de 5 horas";
"settings.appearance.menuBarShowWeek" = "Mostrar uso semanal";
"settings.appearance.menuBarShowFable" = "Mostrar uso de Fable";
"settings.appearance.menuBarShowLabels" = "Mostrar etiquetas (5h / 1w / F)";
```
```
"status.tooltip.usageWithFable %lld %lld %lld" = "5h: %lld%% • Semana: %lld%% • Fable: %lld%%";
```

`de.lproj`:

```
"settings.appearance.menuBarSection" = "Menüleiste";
"settings.appearance.menuBarShow5h" = "5-Stunden-Nutzung anzeigen";
"settings.appearance.menuBarShowWeek" = "Wochennutzung anzeigen";
"settings.appearance.menuBarShowFable" = "Fable-Nutzung anzeigen";
"settings.appearance.menuBarShowLabels" = "Beschriftungen anzeigen (5h / 1w / F)";
```
```
"status.tooltip.usageWithFable %lld %lld %lld" = "5h: %lld%% • Woche: %lld%% • Fable: %lld%%";
```

`fr.lproj`:

```
"settings.appearance.menuBarSection" = "Barre des menus";
"settings.appearance.menuBarShow5h" = "Afficher l'utilisation sur 5 h";
"settings.appearance.menuBarShowWeek" = "Afficher l'utilisation hebdomadaire";
"settings.appearance.menuBarShowFable" = "Afficher l'utilisation de Fable";
"settings.appearance.menuBarShowLabels" = "Afficher les libellés (5h / 1w / F)";
```
```
"status.tooltip.usageWithFable %lld %lld %lld" = "5h : %lld%% • Semaine : %lld%% • Fable : %lld%%";
```

- [ ] **Step 5: Verify no locale was missed**

```bash
cd /Users/shu/workspace/myportfolio/claude.usage
for l in en zh-Hans zh-Hant ja ko es de fr; do
  printf "%-8s keys=%s tooltip=%s\n" "$l" \
    "$(grep -c 'settings.appearance.menuBar' "Apps/ClaudeWatchMac/Resources/$l.lproj/Localizable.strings")" \
    "$(grep -c 'status.tooltip.usageWithFable' "Apps/ClaudeWatchMac/Resources/$l.lproj/Localizable.strings")"
done
```

Expected: every line reads `keys=5 tooltip=1`. Any other number means a locale is missing a string — fix before committing.

Also confirm every locale's tooltip has exactly three `%lld`:

```bash
for l in en zh-Hans zh-Hant ja ko es de fr; do
  printf "%-8s %s\n" "$l" \
    "$(grep 'status.tooltip.usageWithFable' "Apps/ClaudeWatchMac/Resources/$l.lproj/Localizable.strings" | grep -o '%lld' | wc -l | tr -d ' ')"
done
```

Expected: every line reads `3`. A dropped specifier crashes at format time rather than merely looking wrong.

- [ ] **Step 6: Build**

```bash
cd /Users/shu/workspace/myportfolio/claude.usage
xcodegen generate 2>&1 | tail -2
xcodebuild -project ClaudeWatch.xcodeproj \
  -scheme ClaudeWatchMac \
  -configuration Debug \
  -destination 'platform=macOS' \
  build 2>&1 | grep -E "(error:|\*\* )" | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

Write the message to `/tmp/t3.txt`:

```
feat(mac): configurable menu bar segments with immediate refresh

The menu bar now renders any combination of 5h / weekly / Fable,
joined with "/", with an optional short label on each. Four checkboxes
in Settings -> Appearance drive it.

Each toggle posts .menuBarDisplayOptionsChanged, which AppDelegate
observes to re-render. render() otherwise only runs after a poll, so
without this a checkbox would appear to do nothing for up to 90
seconds.

The Fable checkbox is disabled rather than hidden when the account has
no Fable quota — a user on a plan without it should still be able to
see the option exists.

The "no data yet" state keeps its own "⌬ —" and stays ahead of the
formatter. It means the first poll hasn't returned, which is a
different fact from "⌬" with no digits, meaning the user switched
every segment off.

The tooltip carries all three values regardless of what the bar shows:
the bar is what you chose to watch, the tooltip is the full picture. A
second tooltip string is needed because Fable may be absent.

Six new strings across all 8 locales.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
```

```bash
git add Apps/ClaudeWatchMac/AppDelegate.swift \
        Apps/ClaudeWatchMac/Settings/AppearancePane.swift \
        Apps/ClaudeWatchMac/Resources/*.lproj/Localizable.strings
git commit -F /tmp/t3.txt
```

---

## Task 4: Fable line on the 1-week chart

**Files:**
- Modify: `Apps/ClaudeWatchMac/Popover/LineChartView.swift`

**Interfaces:**
- Consumes: `UsageSnapshot.fractionFable: Double?`, `ChartPalette.actualFable` — both already exist.
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Correct the palette's doc comment**

In `Apps/ClaudeWatchMac/Popover/LineChartView.swift`, the `ChartPalette` enum near the top currently reads:

```swift
    /// Fable's identity color. Green (5h) and teal (week) are taken;
    /// purple stays legible in both light and dark popovers and
    /// carries no Anthropic brand association. Used only on the gauge
    /// card — Fable is not plotted on the chart.
    static let actualFable = Color.purple
```

Replace those doc lines with:

```swift
    /// Fable's identity color. Green (5h) and teal (week) are taken;
    /// purple stays legible in both light and dark popovers and
    /// carries no Anthropic brand association. Used by the gauge card
    /// and by the Fable line on the 1w chart, so the two surfaces read
    /// as the same metric.
    static let actualFable = Color.purple
```

- [ ] **Step 2: Add the Fable line**

In the same file, find the weekly-line block inside the `Chart { ... }`:

```swift
            // Weekly actual usage — teal, only on 1w. Sits on the same
            // 0–100% axis as the 5h line, so the two lines stack
            // naturally: weekly is the slow climb, 5h is the saw-tooth
            // that dives on every reset.
            if showsWeekLine {
                ForEach(visible, id: \.timestamp) { s in
                    LineMark(
                        x: .value("t", s.timestamp),
                        y: .value("pct", s.fractionWeek * 100),
                        series: .value("kind", "actualWeek"))
                    .foregroundStyle(ChartPalette.actualWeek)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }
```

Insert this block immediately after it, before the forecast block:

```swift
            // Fable weekly quota — purple, gated on the same condition
            // as the weekly line because Fable is also a weekly window;
            // on an 8h or 24h axis it would be a flat line saying
            // nothing.
            //
            // Snapshots predating the Fable migration carry a nil
            // fractionFable and are skipped, so the line simply starts
            // where the data starts. Zero-filling them would draw a
            // flat run at 0% — a claim that the quota went unused,
            // which is false rather than merely unknown.
            if showsWeekLine {
                ForEach(visible.filter { $0.fractionFable != nil }, id: \.timestamp) { s in
                    LineMark(
                        x: .value("t", s.timestamp),
                        y: .value("pct", (s.fractionFable ?? 0) * 100),
                        series: .value("kind", "actualFable"))
                    .foregroundStyle(ChartPalette.actualFable)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }
```

- [ ] **Step 3: Build**

```bash
cd /Users/shu/workspace/myportfolio/claude.usage
xcodebuild -project ClaudeWatch.xcodeproj \
  -scheme ClaudeWatchMac \
  -configuration Debug \
  -destination 'platform=macOS' \
  build 2>&1 | grep -E "(error:|\*\* )" | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

Write the message to `/tmp/t4.txt`:

```
feat(mac): plot the Fable weekly quota on the 1w chart

Purple line alongside the green 5h and teal weekly lines, gated on the
same timeframe condition as weekly — Fable is a weekly-window quota,
so on an 8h or 24h axis it would be a flat line carrying no
information.

Snapshots predating the Fable migration carry a nil fractionFable and
are filtered out, so the line starts where the data starts. Zero-fill
would draw a flat run at 0%, claiming the quota went unused when the
truth is that it wasn't recorded yet. Expect the line to cover only
the right-hand portion of the 7-day window until roughly a week of
history accumulates.

No legend was added: the three gauge cards above the chart already
carry the color mapping.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
```

```bash
git add Apps/ClaudeWatchMac/Popover/LineChartView.swift
git commit -F /tmp/t4.txt
```

---

## Self-Review

**1. Spec coverage**

| Spec requirement | Task |
|---|---|
| Segments joined with `/`, labels `5h` / `1w` / `F` with `:` | 1 (Step 3) |
| Fixed order 5h → 1w → F | 1 (Step 3, test 7) |
| `nil` Fable drops the segment entirely | 1 (Step 3, test 3) |
| `MenuBarFormatter.segments` returns segments only, no glyph | 1 (Step 3) |
| `MenuBarDisplayOptions.default` = 5h + Fable + labels | 1 (Step 3, test 8) |
| Four `Key` cases stored as `"1"`/`"0"` | 2 (Step 3) |
| `getBool` / `setBool` typed helpers | 2 (Step 3) |
| `render()` composes `⌬ ` + segments, `⌬` when empty | 3 (Step 2) |
| Existing `⌬ —` no-data guard survives | 3 (Step 2) |
| Immediate refresh via notification | 3 (Steps 1, 2, 3) |
| Four checkboxes in Settings → Appearance | 3 (Step 3) |
| Fable checkbox disabled when no Fable quota | 3 (Step 3) |
| Tooltip shows all three values | 3 (Step 2) |
| Two tooltip variants (Fable present / absent) | 3 (Steps 2, 4) |
| 6 new strings × 8 locales | 3 (Step 4, verified Step 5) |
| Purple Fable line, 1w only | 4 (Step 2) |
| Missing history skipped, not zero-filled | 4 (Step 2) |
| `ChartPalette.actualFable` comment corrected | 4 (Step 1) |
| No chart legend | 4 — nothing added, correct |
| 7 formatter tests + 2 settings tests | 1 (Step 1), 2 (Step 1) |

The spec listed 7 formatter cases; the plan writes 8 — the extra one asserts `MenuBarDisplayOptions.default` renders `5h:26%/F:99%`, which is the spec's headline default-behavior claim and was otherwise untested.

No gaps.

**2. Placeholder scan** — no TBD/TODO/"handle edge cases"/"similar to Task N". Every code step carries complete code; every command step carries the exact command and expected output.

**3. Type consistency**

| Name | Defined | Used |
|---|---|---|
| `MenuBarDisplayOptions` (+ 4 fields, memberwise init, `.default`) | Task 1 Step 3 | Task 1 Step 1, Task 3 Steps 2, 3 |
| `MenuBarFormatter.segments(snapshot:options:)` | Task 1 Step 3 | Task 1 Step 1, Task 3 Step 2 |
| `Key.menuBarShow5h` / `Week` / `Fable` / `Labels` | Task 2 Step 3 | Task 2 Step 1, Task 3 Steps 2, 3 |
| `getBool(_:default:)` / `setBool(_:_:)` | Task 2 Step 3 | Task 2 Step 1, Task 3 Steps 2, 3 |
| `Notification.Name.menuBarDisplayOptionsChanged` | Task 3 Step 1 | Task 3 Steps 2, 3 |
| `ChartPalette.actualFable` | pre-existing | Task 4 Steps 1, 2 |
| `status.tooltip.usageWithFable %lld %lld %lld` | Task 3 Step 4 | Task 3 Step 2 |
| `settings.appearance.menuBar*` (5 keys) | Task 3 Step 4 | Task 3 Step 3 |

All names agree across tasks. `AppearancePane.write(_:_:)` takes `SettingsRepository.Key`, matching the enum's fully-qualified name as it must be referenced from the app target.
