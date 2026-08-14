# Configurable Menu Bar Segments + Fable Chart Line — Design

**Date:** 2026-08-15
**Status:** Approved
**Target release:** v0.1.9

---

## Goal

Two changes that finish surfacing the Fable quota, which the previous release only exposed inside the popover:

1. **Make the menu bar show up to three percentages** — 5h, weekly, and Fable — with a checkbox per segment and a fourth checkbox for labels.
2. **Plot Fable on the 1-week chart** alongside the existing 5h and weekly lines.

The problem both solve: after the previous release, a user whose Fable quota sits at 99% still sees `⌬ 26%` in the always-visible surface. The number that actually blocks them is one click away, behind a popover.

---

## Background

The menu bar currently renders a single value, hardcoded to 5h (`AppDelegate.render()`):

```swift
let pct = Int(snap.fraction5h * 100)
statusItem.setText("⌬ \(pct)%", tooltip: ...)
```

The 1-week chart draws two series — `fraction5h` in green and `fractionWeek` in teal — gated on `showsWeekLine = (timeframe == .oneWeek)`. `ChartPalette.actualFable` (purple) already exists from the previous release but is used only by the gauge card; its doc comment currently says "Used only on the gauge card — Fable is not plotted on the chart."

---

## Scope

### In scope

- Four persisted settings: show-5h, show-week, show-Fable, show-labels.
- A pure, unit-testable formatter that turns a snapshot plus those settings into the menu bar string.
- Four checkboxes in Settings → Appearance, with the Fable one disabled when the account has no Fable quota.
- Immediate menu bar refresh when a checkbox changes — not deferred to the next 90 s poll.
- A purple Fable line on the 1-week chart.
- A tooltip that shows all three values regardless of checkbox state.

### Out of scope

- **Custom segment ordering.** Fixed 5h → 1w → Fable. Drag-to-reorder is a preferences-UI project for a three-item list.
- **Fable in `AlertEngine`.** Threshold alerts still fire only on 5h and weekly. Wiring Fable into alerting means deciding new default thresholds and new notification copy — its own spec.
- **Fable on the 8h / 24h charts.** Fable is a weekly-window quota; plotting it against an 8-hour x-axis shows a flat line that means nothing.
- **Fable in `DataPane.exportCSV`.** Known gap, tracked separately.
- **A chart legend.** The three gauge cards already legend the three lines by color.

---

## Part 1 — Menu bar

### Rendered output

Segments are joined with `/`. Labels are `5h`, `1w`, `F`.

```
labels off, all three     ⌬ 26%/69%/99%
labels on,  all three     ⌬ 5h:26%/1w:69%/F:99%
labels on,  5h + Fable    ⌬ 5h:26%/F:99%
labels off, 5h only       ⌬ 26%
nothing selected          ⌬
```

`5h` and `1w` keep two characters rather than collapsing to `H` and `W` because they are the app's existing vocabulary — the popover's timeframe picker already reads `8h 24h 1w 1m`. Introducing a second shorthand for the same windows would cost more in confusion than the two characters save. `F` has no such conflict.

### The formatter

Lives in `Packages/UsageCore/Sources/UsageCore/Formatting/MenuBarFormatter.swift` so it can be unit-tested — `AppDelegate` is not reachable from `UsageCoreTests`.

```swift
public struct MenuBarDisplayOptions: Equatable {
    public var show5h: Bool
    public var showWeek: Bool
    public var showFable: Bool
    public var showLabels: Bool

    public static let `default` = MenuBarDisplayOptions(
        show5h: true, showWeek: false, showFable: true, showLabels: true)
}

public enum MenuBarFormatter {
    /// Returns only the segment string — no glyph, no leading space.
    /// The caller composes the final title, because the "⌬" is a
    /// presentation choice belonging to the macOS app, not to this
    /// platform-agnostic package.
    ///
    /// Returns "" when nothing is selected, when every selected
    /// segment is unavailable, or when `snapshot` is nil.
    public static func segments(snapshot: UsageSnapshot?,
                                options: MenuBarDisplayOptions) -> String
}
```

Rules:

- Percentages are `Int(fraction * 100)` — same rounding the current code uses.
- A segment is emitted only if its checkbox is on **and** its value exists. `fractionFable` is `Double?`; a `nil` drops the segment entirely rather than rendering `F:0%` or leaving `//`.
- Order is always 5h, 1w, F, regardless of which are enabled.

`AppDelegate.render()` composes: a non-empty result becomes `"⌬ \(segments)"`, an empty result becomes `"⌬"`.

**The existing no-data state must survive.** `render()` today starts with `guard let snap = ctx.controller?.state.latest else { setText("⌬ —", tooltip: "No data"); return }`, which distinguishes "the first poll hasn't returned yet" from "you have selected nothing to display". That guard stays exactly where it is and keeps its `⌬ —`; the formatter is only reached once a snapshot exists. The formatter's own nil-snapshot case returns `""` purely so the function is total — it is not the path that renders the no-data indicator, and collapsing the two would lose a genuinely useful signal on first launch.

### Settings storage

`SettingsRepository.Key` gains four cases. Values are stored as `"1"` / `"0"`.

```swift
case menuBarShow5h
case menuBarShowWeek
case menuBarShowFable
case menuBarShowLabels
```

Because the repository's `get` returns `String?` and every one of these needs a non-nil default, add two typed helpers rather than repeating the parse at each call site:

```swift
public func getBool(_ key: Key, default def: Bool) throws -> Bool
public func setBool(_ key: Key, _ value: Bool) throws
```

`getBool` returns `def` when the key is absent or holds anything other than `"1"` / `"0"`.

### Defaults

| Setting | Default |
|---|---|
| `menuBarShow5h` | on |
| `menuBarShowWeek` | off |
| `menuBarShowFable` | on |
| `menuBarShowLabels` | on |

Rendering `⌬ 5h:26%/F:99%` out of the box.

This deliberately changes the menu bar's appearance for existing users rather than preserving today's `⌬ 26%`. The reason: a default of 5h-only reproduces exactly the problem this release exists to fix — anyone who never opens Settings keeps a menu bar that stays quiet while their Fable quota is exhausted. Weekly defaults off because it is the slowest-moving of the three and costs the most width for the least information.

When the account has no Fable quota the Fable segment is simply absent, so those users see `⌬ 5h:26%` — narrower than today, not wider.

### Refresh on change

`render()` currently runs only after a poll completes, so a checkbox toggle would take up to 90 seconds to appear. That is unacceptable for a settings control the user is looking at.

`AppearancePane` posts `Notification.Name.menuBarDisplayOptionsChanged` after writing a setting; `AppDelegate` observes it and calls `render()`. A notification rather than a direct reference keeps the settings pane from having to reach into the app delegate, matching how the pane already avoids touching AppKit specifics.

### Settings UI

Settings → Appearance, in a new section below the existing theme picker:

```
Menu bar
  ☑ Show 5-hour usage
  ☐ Show weekly usage
  ☑ Show Fable usage          (disabled when the account has no Fable quota)
  ☑ Show labels (5h / 1w / F)
```

The Fable checkbox's enabled state comes from `ctx.controller?.state.latest?.fractionFable != nil`, read on appear. A disabled checkbox is better than a hidden one: it tells a user on a plan without Fable that the feature exists rather than leaving them wondering.

### Tooltip

The tooltip shows all three values regardless of checkbox state — the menu bar is what the user chose to watch, the tooltip is the full picture. Two variants, because Fable may be absent:

- `status.tooltip.usage %lld %lld` — unchanged: `5h: %lld%% • Week: %lld%%`
- `status.tooltip.usageWithFable %lld %lld %lld` — new: `5h: %lld%% • Week: %lld%% • Fable: %lld%%`

---

## Part 2 — Fable line on the 1-week chart

- **Color:** `ChartPalette.actualFable` (purple, already defined). Its doc comment must drop the "not plotted on the chart" sentence, which this change makes false.
- **Gating:** same condition as the weekly line — drawn only when `timeframe == .oneWeek`. Fable is a weekly-window quota; on an 8-hour axis it would be a meaningless flat line.
- **Missing history:** snapshots written before the previous release's migration have `usedFable == nil`. Those points are skipped, so the line simply starts where the data starts. No placeholder, no zero-fill — a zero-filled Fable line would read as "you used nothing", which is false rather than merely absent.
- **No legend:** the three gauge cards above the chart already carry the color mapping (green 5h, teal Week, purple Fable).

**Known cosmetic consequence:** the Fable line will cover only the portion of the 7-day window that postdates the migration. For roughly the first week after this ships it will be a short segment on the right-hand side of an otherwise 7-day chart. This is correct behavior — the data genuinely does not exist — and it resolves itself as history accumulates.

---

## Files

| File | Change |
|---|---|
| `Packages/UsageCore/Sources/UsageCore/Formatting/MenuBarFormatter.swift` | New — `MenuBarDisplayOptions` + `segments(snapshot:options:)` |
| `Packages/UsageCore/Sources/UsageCore/Storage/SettingsRepository.swift` | +4 `Key` cases, +`getBool`/`setBool` |
| `Packages/UsageCore/Tests/UsageCoreTests/Formatting/MenuBarFormatterTests.swift` | New — formatter cases |
| `Apps/ClaudeWatchMac/AppDelegate.swift` | `render()` uses the formatter; observes the refresh notification; 3-value tooltip |
| `Apps/ClaudeWatchMac/Settings/AppearancePane.swift` | +4 checkboxes, +notification post |
| `Apps/ClaudeWatchMac/Popover/LineChartView.swift` | +Fable `LineMark`; fix `ChartPalette.actualFable` doc comment |
| `Apps/ClaudeWatchMac/Resources/*.lproj/Localizable.strings` × 8 | +6 strings |

New localized keys:

| Key | en |
|---|---|
| `settings.appearance.menuBarSection` | `Menu bar` |
| `settings.appearance.menuBarShow5h` | `Show 5-hour usage` |
| `settings.appearance.menuBarShowWeek` | `Show weekly usage` |
| `settings.appearance.menuBarShowFable` | `Show Fable usage` |
| `settings.appearance.menuBarShowLabels` | `Show labels (5h / 1w / F)` |
| `status.tooltip.usageWithFable %lld %lld %lld` | `5h: %lld%% • Week: %lld%% • Fable: %lld%%` |

---

## Testing

### Unit tests — `MenuBarFormatterTests`

The formatter is the only part of this work with logic worth asserting; everything else is wiring verified by build plus the manual pass.

1. **`allThreeWithLabels`** — all on, labels on, snapshot with Fable → `"5h:26%/1w:69%/F:99%"`.
2. **`allThreeWithoutLabels`** — all on, labels off → `"26%/69%/99%"`.
3. **`fableAbsent_dropsSegmentEntirely`** — all on, labels on, `usedFable == nil` → `"5h:26%/1w:69%"`, with no trailing `/` and no `F:0%`.
4. **`nothingSelected_returnsEmpty`** — all four off → `""`.
5. **`nilSnapshot_returnsEmpty`** — `snapshot: nil` → `""`.
6. **`singleSegmentNoLabel`** — only 5h, labels off → `"26%"` (proves no stray separator on a one-segment render).
7. **`orderIsFixedRegardlessOfSelection`** — only Fable and weekly enabled → `"1w:69%/F:99%"`, proving 1w precedes F even though 5h is skipped.

### Unit tests — `SettingsRepository`

8. **`getBool_absentKey_returnsDefault`** — unset key with `default: true` → `true`.
9. **`setBoolThenGetBool_roundTrips`** — write `false`, read back `false` (guards against the "1"/"0" parse treating any non-empty string as true).

### Manual verification

- Toggle each checkbox and confirm the menu bar updates **immediately**, not after the next poll.
- Uncheck all three value boxes → menu bar shows only `⌬`.
- Hover the menu bar icon → tooltip lists all three values regardless of which boxes are checked.
- Open the popover on 1w → a purple Fable line appears alongside green and teal, starting where Fable history begins.
- Confirm the widest configuration (`⌬ 5h:26%/1w:69%/F:99%`) does not push other menu bar items off-screen on the primary display.
