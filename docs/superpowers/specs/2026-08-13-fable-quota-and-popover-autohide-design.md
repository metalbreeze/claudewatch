# Fable Weekly Quota + Popover Auto-Hide — Design

**Date:** 2026-08-13
**Status:** Approved
**Target release:** v0.1.9

---

## Goal

Two independent user-facing changes:

1. **Surface the Fable weekly quota.** Anthropic added a per-model weekly limit that the app currently ignores. The user's Fable quota is at 99% while the two gauges the app *does* show read 26% and 69% — the app is hiding the only number that matters.
2. **Make the popover dismiss itself.** Today it never closes on its own: clicking elsewhere leaves it open (a bug), and there is no idle timeout.

---

## Background: the `/usage` API changed

Live response captured 2026-08-13 (abridged):

```json
{
  "five_hour":  { "utilization": 26.0, "resets_at": "2026-08-13T15:09:59.783360+00:00" },
  "seven_day":  { "utilization": 69.0, "resets_at": "2026-08-13T21:00:00.783384+00:00" },
  "seven_day_opus": null, "seven_day_sonnet": null, "nimbus_quill": { ... },
  "limits": [
    { "kind": "session",       "group": "session", "percent": 26, "severity": "normal",
      "resets_at": "2026-08-13T15:09:59.783360+00:00", "scope": null, "is_active": false },
    { "kind": "weekly_all",    "group": "weekly",  "percent": 69, "severity": "normal",
      "resets_at": "2026-08-13T21:00:00.783384+00:00", "scope": null, "is_active": false },
    { "kind": "weekly_scoped", "group": "weekly",  "percent": 99, "severity": "critical",
      "resets_at": "2026-08-13T20:59:59.783618+00:00",
      "scope": { "model": { "id": null, "display_name": "Fable" }, "surface": null },
      "is_active": true }
  ]
}
```

Three facts drive the design:

- **Fable lives in the new `limits[]` array**, identified by `scope.model.display_name`. It is *not* in any of the codename fields (`seven_day_opus`, `nimbus_quill`, `tangelo`, …) — those are all `null` for this account.
- **The legacy `five_hour` / `seven_day` top-level objects still exist** and agree with the `session` / `weekly_all` entries in `limits[]`. Existing parsing keeps working untouched.
- **`is_active` marks the binding constraint.** Anthropic tells us which limit is actually throttling the user right now. Here it is Fable at 99% — exactly the signal the current UI lacks.

---

## Scope

### In scope

- Parse `limits[]`, extract the `weekly_scoped` entry whose `scope.model.display_name == "Fable"`.
- Persist Fable utilization / reset time / active flag alongside every snapshot.
- Render a third gauge card for Fable, shown only when the API reports one.
- Visually mark whichever gauge the API flags `is_active`.
- Close the popover on outside click (fixes the broken `.transient` behavior).
- Close the popover after 10 continuous seconds with the mouse outside it and no keyboard focus in it.

### Out of scope

- **Generic scoped-limit support.** We hardcode Fable rather than rendering every `weekly_scoped` entry. Anthropic is clearly moving toward a dynamic limits list, so this will likely need revisiting — but a generic model means a variable-length window list in `UsageSnapshot` and a child table in SQLite, roughly 3× the work. Deferred until a second scoped limit actually appears.
- **A Fable line in the chart.** The 1w view already draws two lines; a third would crowd it, and Fable history only starts accumulating after this release ships, so the left portion of any Fable line would be empty for weeks. Revisit once there is data worth plotting.
- **Configurable auto-hide delay.** 10 seconds is a constant. A Settings control means 8 more localized strings for a value the author can change by editing one line. Revisit if App Store users ask.
- **`severity`, `group`, `spend`, `extra_usage`, `member_dashboard_available`.** Parsed-over, not stored.

---

## Part 1 — Fable weekly quota

### Data model

`UsageSnapshot` gains three optional fields. All existing initializer call sites keep compiling because the new parameters default to `nil` / `false`:

```swift
public let usedFable: Int?          // 0–10000, same 100×-percent scale as used5h
public let resetTimeFable: Date?
public let fableIsActive: Bool      // API's is_active for the Fable limit

public var fractionFable: Double? {
    guard let u = usedFable else { return nil }
    return min(1.0, Double(u) / 10_000)
}
```

`nil` means "the API reported no Fable limit for this account" — not all plans have one. Every UI surface treats `nil` as "hide the Fable card".

### Parsing

`JSONUsageScraper.Response` gains an **optional** `limits` array. Optional is load-bearing: an older or regional API response without the field must not trip `ScrapeError.schemaDrift`.

```swift
private struct Response: Decodable {
    let five_hour: Window?
    let seven_day: Window?
    let limits: [Limit]?          // optional — absent on older API shapes

    struct Window: Decodable {
        let utilization: Double
        let resets_at: Date?
    }

    struct Limit: Decodable {
        let kind: String?
        let percent: Double?
        let resets_at: Date?
        let is_active: Bool?
        let scope: Scope?

        struct Scope: Decodable {
            let model: Model?
            struct Model: Decodable { let display_name: String? }
        }
    }
}
```

Extraction, applied after decoding:

```swift
let fable = r.limits?.first {
    $0.kind == "weekly_scoped" &&
    $0.scope?.model?.display_name == "Fable"
}
let usedFable = fable?.percent.map { Int(($0 * 100).rounded()) }
```

The `× 100` keeps Fable on the same 0–10000 scale as `used5h` / `usedWeek`, so a single ceiling constant (10 000) covers all three and `fraction*` accessors stay uniform.

Matching is on the exact string `"Fable"`. If Anthropic renames the display name, the card disappears rather than showing wrong data — an acceptable failure mode for a hardcoded approach, and the reason the generic design is the eventual destination.

### Persistence

Migration `v2` adds three nullable columns to `snapshots`:

```sql
ALTER TABLE snapshots ADD COLUMN used_fable INTEGER;
ALTER TABLE snapshots ADD COLUMN reset_fable INTEGER;
ALTER TABLE snapshots ADD COLUMN fable_is_active INTEGER NOT NULL DEFAULT 0;
```

Rows written before this release read back as `usedFable = nil`, which the UI already handles. `snapshots_5min` is **not** changed — the rollup table feeds long-range chart aggregation, and we are not charting Fable.

`SnapshotRepository.insert` writes the three columns; `fromRow` reads them with nullable subscripting.

### UI — three gauge cards

Content width is 316 pt (340 pt popover − 12 pt padding × 2). With two 10 pt gaps, three cards are **98.7 pt** each, giving 78.7 pt of inner width after the card's 10 pt padding.

```
┌──────────┐ ┌──────────┐ ┌──────────┐
│ 5H       │ │ WEEK     │ │ FABLE    │
│ 26%      │ │ 69%      │ │ 99%      │
│ ▓▓░░░░░░ │ │ ▓▓▓▓▓▓░░ │ │ ▓▓▓▓▓▓▓▓ │
│ 0h56m    │ │ Thu      │ │ Thu      │
└──────────┘ └──────────┘ └──────────┘
   98.7pt       98.7pt       98.7pt
```

- `100%` at 28 pt rounded ≈ 62 pt — fits inside 78.7 pt.
- The current reset captions do not fit and must be shortened:
  - 5h: `resets in 0h 56m` → `0h56m`
  - week / Fable: `resets Thu` → `Thu`
- When `fractionFable == nil`, the third card is omitted and the remaining two expand back to 153 pt each — no separate layout branch needed, `frame(maxWidth: .infinity)` handles it.

Popover height is unchanged; only card width shrinks.

### Active-limit emphasis

Whichever gauge the API marks `is_active` gets a 1 pt border in its tint color. `GaugeCardView` gains an `isActive: Bool` parameter defaulting to `false`.

This matters because the danger coloring alone is misleading here: at 26% / 69% / 99%, only the Fable number turns red, but nothing tells the user that Fable is a *scoped* limit whose exhaustion blocks one model rather than the whole account. The border says "this is the one currently stopping you."

Only `is_active` from the Fable limit is stored, so in practice only the Fable card can show the border in v0.1.9. Storing per-window active flags for 5h and week is deferred with the rest of the generic-limits work.

### Color

`ChartPalette` gains `actualFable` — **purple**. Green (5h) and teal (week) are taken; purple reads clearly in both light and dark themes and carries no Anthropic brand association.

The Fable card is not represented in the chart, so this color appears only on the gauge label, fill bar, and active border.

### Localization

New key `popover.gauge.fable` = `Fable` (untranslated — it is a product name) across all 8 locales.

The compact reset captions replace the existing verbose ones:

| Key | Before (en) | After (en) |
|---|---|---|
| `popover.reset.resetsIn %lld %lld` | `resets in %lldh %lldm` | `%lldh%lldm` |
| `popover.reset.resetsOn %@` | `resets %@` | `%@` |

All 8 locales get the shortened forms. The information loss ("resets" wording) is acceptable: the caption sits directly under a labeled gauge, and the surrounding context makes it unambiguous.

---

## Part 2 — Popover dismissal

### Why `.transient` does not work today

`PopoverController` sets `popover.behavior = .transient` but never activates the app. In an `LSUIElement: YES` process, clicking the status item does not make the app active, and `.transient` dismissal depends on the app receiving the outside-click event. The app never becomes active, so the event never arrives, so the popover stays open indefinitely.

The obvious fix — `NSApp.activate(ignoringOtherApps: true)` before `show` — is rejected: it steals keyboard focus from whatever the user was doing. For glance-at-a-number UI that is too disruptive. Instead we detect outside clicks ourselves.

### Three dismissal triggers

| Trigger | Mechanism | Status |
|---|---|---|
| Click the menu bar icon again | `toggle()` calls `performClose` | already works |
| Click anywhere outside the popover | Global `NSEvent` monitor | **fix** |
| Mouse outside popover for 10 s | Polling timer | **new** |

### Outside-click monitor

On show, install:

```swift
NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
    self?.popover.performClose(nil)
}
```

Global monitors only fire for events delivered to *other* applications, so clicks inside the popover never reach this handler — no self-dismissal guard needed. The monitor is torn down on close.

### Idle timer

A `Timer` firing every 0.5 s while the popover is shown:

```
if mouse is inside the popover's window frame  → reset elapsed to 0
else if the popover's window is key            → reset elapsed to 0
else                                            → elapsed += 0.5
if elapsed >= 10.0                              → performClose
```

Mouse position comes from `NSEvent.mouseLocation` (screen coordinates) tested against `popover.contentViewController?.view.window?.frame`. Polling is chosen over `NSTrackingArea` because tracking areas inside an `NSHostingController`'s SwiftUI view hierarchy are fragile across re-renders, and the popover rebuilds its content tree on every open. A 0.5 s timer costs nothing at this scale.

The key-window check keeps the popover open while the user is actually interacting with it via keyboard — clicking a timeframe button activates the app and makes the popover key, so mid-interaction dismissal cannot happen even if the mouse drifts out.

Both the timer and the event monitor are created on show and invalidated on close, in one place, so neither can leak or outlive the popover.

`10.0` and `0.5` are named constants at the top of `PopoverController`.

---

## Files

| File | Change |
|---|---|
| `Packages/UsageCore/Sources/UsageCore/Models/UsageSnapshot.swift` | +3 fields (defaulted), +`fractionFable` |
| `Packages/UsageCore/Sources/UsageCore/Scraping/JSONUsageScraper.swift` | +`limits` decoding, Fable extraction |
| `Packages/UsageCore/Sources/UsageCore/Storage/Database.swift` | +migration `v2` |
| `Packages/UsageCore/Sources/UsageCore/Storage/SnapshotRepository.swift` | insert/read the 3 columns |
| `Apps/ClaudeWatchMac/Popover/LineChartView.swift` | +`ChartPalette.actualFable` |
| `Apps/ClaudeWatchMac/Popover/GaugeCardView.swift` | +`isActive` border |
| `Apps/ClaudeWatchMac/Popover/PopoverRootView.swift` | conditional third card, compact captions |
| `Apps/ClaudeWatchMac/Popover/PopoverController.swift` | event monitor + idle timer |
| `Apps/ClaudeWatchMac/Resources/*.lproj/Localizable.strings` × 8 | +`popover.gauge.fable`, shortened captions |

---

## Testing

### Unit tests — `JSONUsageScraper` parsing

Fixtures are JSON literals in the test file; the scraper is driven through a stubbed `URLSession` (`URLProtocol` subclass returning canned data), matching the pattern already used by the existing scraper tests.

1. **`limits_withFable_extractsUtilizationAndReset`** — full 3-entry `limits[]`; asserts `usedFable == 9900`, `fableIsActive == true`, `resetTimeFable` parsed.
2. **`limits_withoutFable_yieldsNilFable`** — `limits[]` present but containing only `session` and `weekly_all`; asserts `usedFable == nil`, `fableIsActive == false`.
3. **`limitsFieldAbsent_doesNotThrowSchemaDrift`** — the pre-change response shape with no `limits` key at all; asserts a snapshot decodes with `used5h` / `usedWeek` populated and `usedFable == nil`.
4. **`limits_scopedButDifferentModel_yieldsNilFable`** — a `weekly_scoped` entry whose `display_name` is `"Opus"`; asserts `usedFable == nil` (guards against matching on `kind` alone).

### Unit test — migration

5. **`migrationV2_preservesExistingRowsWithNullFable`** — open an in-memory DB, run migration `v1` only, insert a row via raw SQL, run the full migrator, then read through `SnapshotRepository` and assert the row survives with `usedFable == nil`.

### Manual verification

- Popover shows three cards; Fable card carries a purple border (it is `is_active`).
- Click on the desktop → popover closes immediately.
- Open the popover, move the mouse away, do not click → closes after ~10 s.
- Open the popover, keep the mouse over it → stays open indefinitely.
- Click a timeframe button, then move the mouse away → still closes after ~10 s.
- Switch to a Claude account with no Fable limit (or stub the response) → two cards at the original 153 pt width, popover otherwise unchanged.
