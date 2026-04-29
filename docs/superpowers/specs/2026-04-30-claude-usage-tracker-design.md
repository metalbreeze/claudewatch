# Claude Usage Tracker — Design Spec

**Date:** 2026-04-30
**Status:** Approved (brainstorming complete; pre-implementation)
**Platforms:** macOS (menu bar app, primary) + iOS (full app + widgets)
**Data source:** Scrape `https://claude.ai/settings/usage` via authenticated WKWebView session.

## 1. System overview & data flow

A native SwiftUI app that displays Claude.ai / Claude Code product usage (5-hour rolling window + weekly window) on macOS and iOS. The macOS app runs as a menu bar resident (`LSUIElement`) showing the current 5h percentage at a glance; clicking the menu bar opens a popover with both gauges, history charts (1h/8h/24h/1w), and a forecast. The iOS app provides feature parity through a single scrollable screen plus home-screen and lock-screen widgets.

Each device polls `claude.ai` independently every 90 seconds (with ±10s jitter). Snapshots land in a local SQLite cache and asynchronously sync to a CloudKit private database, so the iPhone shows charts populated by Mac data and vice versa. CloudKit syncs derived data only — auth credentials are not synced.

### 1.1 Components

```
macOS app (LSUIElement, menu bar)
├── NSStatusItem (display: "⌬ 47%")
├── UsageCore (Swift Package, shared)
│   ├── Scraper (intercepts /api/.../usage JSON every 90s)
│   ├── SQLite cache (~/Library/Application Support/.../usage.db)
│   ├── Forecaster (linear + hour-of-day baseline)
│   └── CloudKit private DB sync
├── Local Keychain (auth cookie, cf_clearance, User-Agent)
└── WKWebView (login surface, hidden cf_clearance refresh)

iOS app + Widget extension
├── SwiftUI screens
├── WidgetKit extension (small / medium / large + lock-screen)
├── UsageCore (same Swift Package)
│   ├── Scraper (own 90s polling)
│   ├── SQLite cache (App Group container, shared with widget)
│   ├── Forecaster
│   └── CloudKit private DB sync
├── Local Keychain (own auth cookie, NOT iCloud-synced)
└── WKWebView (login surface)
```

### 1.2 Per-poll data flow

1. Timer fires (90s ± jitter).
2. Scraper checks cookie validity. If invalid → mark device "needs re-auth" and surface banner.
3. If valid, send `GET` to the JSON usage endpoint with stored cookies + User-Agent.
4. Parse → `UsageSnapshot`.
5. Insert into local SQLite (`snapshots` table).
6. Compute current %, forecast, alert state.
7. Push to UI (menu bar text, popover, widget timeline reload).
8. Async upload snapshot to CloudKit (debounced; ≤ once per 5 min, batched).

### 1.3 Why each device polls independently

Simpler than designating a primary. Resilient to Mac being asleep. Polling is cheap enough at 90s that double-polling is acceptable. CloudKit is the merge point — both devices write timestamped snapshots; the local cache deduplicates by `(device_id, ts)` on read.

## 2. Authentication flow

### 2.1 First run on either device

1. App opens → no session cookie in local Keychain → present `WKWebView` covering the screen (Mac: ~500×700pt window; iOS: full-screen sheet).
2. WebView loads `https://claude.ai/login`. User logs in via their normal flow (email magic link, Google SSO, or password).
3. On detecting a logged-in URL (`/chats`, `/settings`, etc.), `WKNavigationDelegate`:
   - Reads cookies from `WKWebsiteDataStore.default().httpCookieStore`.
   - Stores them in **local** Keychain (NOT iCloud-synced) under `service: com.claudeusage.cookie`, `account: device_id`. Stored fields: `sessionKey` (Anthropic auth), `cf_clearance`, `__cf_bm`, plus the WKWebView's User-Agent string.
   - Dismisses the web view → first poll fires.

`device_id` is a UUID generated on first run, persisted in the local Keychain (and never rotated). On macOS it's separate from any hardware ID; on iOS it's separate from `identifierForVendor`. This keeps `device_id` stable across reinstall as long as the Keychain entry survives, and lets us identify "Mac" vs "iPhone" in `Devices syncing` UI without exposing real device identifiers.

### 2.2 Steady-state polls (90s ± 10s jitter)

- `URLSession` request to the JSON usage endpoint with stored cookies + matching User-Agent header.
- **200** → parse + store snapshot.
- **401 / 403 (auth)** → mark "needs re-auth," surface banner ("Your Claude.ai session expired. Tap to re-login"), stop polling on that device until user re-authenticates.
- **403 with Cloudflare challenge HTML** → automatically reload `claude.ai` once in a 1×1px hidden WKWebView to re-acquire `cf_clearance`, refresh Keychain cookies, retry the poll. Surface the banner only if auto-recovery fails twice.
- **429** → exponential backoff: skip the next 1, 2, 4, 8 polls (cap at 8), resume on first success.

### 2.3 Logout

Settings → "Sign out of this device" → wipes Keychain entry + clears WKWebView cookie store + stops polling. Does not touch the other device or CloudKit history.

### 2.4 Why no cross-device cookie sharing

`cf_clearance` is bound to User-Agent + IP fingerprint and is not shareable. The only meaningful win from iCloud-syncing the auth cookie would be skipping the SSO step on device #2; the complexity (token-lifetime variance, SSO-cookie variance) outweighs ~30 seconds of one-time login friction. Each device authenticates independently.

## 3. Scraping & parsing

### 3.1 Endpoint discovery (implementation step 1)

The exact JSON endpoint is **TBD by inspection**. The first implementation task is to open `https://claude.ai/settings/usage` in Safari/Chrome DevTools, watch the **Network** tab, and identify the actual XHR/fetch URL the page uses. Likely shape: `/api/organizations/{org_id}/usage` or similar. Do not hardcode an endpoint until verified.

### 3.2 Scraper interface

```swift
protocol UsageScraper {
    /// Fetches a fresh snapshot. Throws on auth, network, or schema-drift failures.
    func fetchSnapshot() async throws -> UsageSnapshot
    var sourceVersion: String { get }   // e.g. "json-v1", "html-v1"
}

struct UsageSnapshot {
    let timestamp: Date
    let plan: String              // "Pro" / "Max 5x" / "Max 20x" / "Team" / "Free"
    let used5h: Int               // tokens consumed in current 5h rolling window
    let ceiling5h: Int            // 5h token cap as reported by the page
    let resetTime5h: Date         // when the 5h window resets
    let usedWeek: Int
    let ceilingWeek: Int
    let resetTimeWeek: Date
    let raw: Data                 // original payload, kept for debugging
}
```

### 3.3 Two implementations

1. **`JSONUsageScraper` (preferred).** Once the endpoint is known, `URLSession` with stored cookies + User-Agent. Parses JSON via `Codable`. Fast (~50ms per poll), low overhead, robust to small UI changes.
2. **`HTMLUsageScraper` (fallback).** Loads `https://claude.ai/settings/usage` in a hidden WKWebView, runs `evaluateJavaScript(...)` to extract values from React state or DOM. Slower (~1-2s per poll), more brittle, but always works.

`ScraperFactory.current()` returns JSON if it succeeded last time, else falls back to HTML, else marks the device "scraper failure" and surfaces a banner.

### 3.4 Schema-drift resilience

- Every snapshot stores `sourceVersion`. Old rows remain readable when we ship `json-v2`.
- Parser failures throw structured `ScrapeError` — never silently zero out values. Popover shows "Source format changed — update the app."
- Last 5 raw payloads kept in `~/Library/Application Support/.../debug-payloads/` for bug reports.

### 3.5 Polling timer behavior

- `Timer.publish(every: 90, on: .main, in: .common)` while app is foreground / menu bar resident.
- Skip next tick if previous is still in flight (no parallel polls).
- iOS background-restriction-aware: iOS may only wake the widget every 15-30 min in the background; that's accepted.
- macOS: back off to 5-min cadence if no UI events for >10 min (battery courtesy).

## 4. Data model & storage

### 4.1 Three storage layers

| Layer | Where | What | Why |
|---|---|---|---|
| Keychain | Local (per device) | Auth cookies, `cf_clearance`, `User-Agent`, plan-tier override | Sensitive; never leaves device |
| SQLite | App Support (Mac), App Group container (iOS — shared with widget) | Snapshot history, alert state, settings | Fast reads for popover/widget; survives restart |
| CloudKit private DB | iCloud (per Apple ID) | Aggregated history, settings | Cross-device merge; free tier covers it |

### 4.2 SQLite schema (`usage.db`, managed via GRDB)

```sql
CREATE TABLE snapshots (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id       TEXT NOT NULL,
    ts              INTEGER NOT NULL,
    plan            TEXT NOT NULL,
    used_5h         INTEGER NOT NULL,
    ceiling_5h      INTEGER NOT NULL,
    reset_5h        INTEGER NOT NULL,
    used_week       INTEGER NOT NULL,
    ceiling_week    INTEGER NOT NULL,
    reset_week      INTEGER NOT NULL,
    source_version  TEXT NOT NULL,
    synced_to_cloud INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX idx_snapshots_ts ON snapshots(ts);

CREATE TABLE snapshots_5min (
    -- 5-minute downsampled snapshots, populated by hourly retention job
    bucket_start    INTEGER NOT NULL,    -- unix seconds, aligned to 5-min boundary
    device_id       TEXT NOT NULL,
    plan            TEXT NOT NULL,
    used_5h_avg     INTEGER NOT NULL,
    ceiling_5h      INTEGER NOT NULL,
    used_week_avg   INTEGER NOT NULL,
    ceiling_week    INTEGER NOT NULL,
    bucket_count    INTEGER NOT NULL,    -- how many raw rows were averaged
    PRIMARY KEY (bucket_start, device_id)
);
CREATE INDEX idx_snapshots_5min_bucket ON snapshots_5min(bucket_start);

CREATE TABLE settings (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

CREATE TABLE alert_state (
    kind          TEXT PRIMARY KEY,
    last_fired_at INTEGER,
    snoozed_until INTEGER
);
```

### 4.3 Retention

- Raw 90s snapshots live in the `snapshots` table for **7 days**.
- An hourly retention job aggregates rows older than 7 days into 5-minute buckets, writes them into a separate `snapshots_5min` table (same columns, plus `bucket_count` and averaged numeric fields), then deletes the raw rows. Charts beyond 7 days read from `snapshots_5min`; charts within 7 days read from `snapshots`.
- Rows in `snapshots_5min` older than **30 days** are deleted.
- Rationale for the separate table: keeps the hot path (1h / 8h chart, popover render) untouched by historical bulk; downsampled rows have a different cardinality so mixing them in the raw table would complicate every query.

### 4.4 CloudKit record types

```
CKRecord("UsageSnapshot")
  fields: ts, plan, used_5h, ceiling_5h, reset_5h, used_week, ceiling_week,
          reset_week, source_version, device_id
  recordName: "{device_id}-{ts}"   ← natural key prevents duplicate writes

CKRecord("Settings")
  fields: alert_thresholds (JSON), plan_override, theme, etc.
  recordName: "settings-singleton"
```

### 4.5 Sync strategy

- Local writes hit SQLite immediately.
- CloudKit upload is debounced: at most once per 5 min, batching accumulated snapshots.
- On launch, fetch CloudKit records newer than `last_sync_ts`; insert into SQLite (deduplicated by `recordName`).
- Conflict resolution: snapshots are write-once and identified by `(device_id, ts)`, so duplicates are dropped silently. Settings use last-write-wins via `CKServerChangeToken`.

### 4.6 Widget access

The iOS widget extension must render in <100ms with no network. SQLite in the App Group container is reachable from the widget. The widget reads the most recent snapshot row directly. Network polling stays in the main app process — the widget never invokes the scraper.

## 5. Forecast math

Two independent forecasts.

### 5.1 Short-term linear extrapolation (used on 1h / 8h charts)

**Goal:** predict when `used_5h` will hit `ceiling_5h` at the current burn rate.

**Inputs:** snapshots in the last `W` minutes, where `W = min(60, time-since-current-5h-window-started)`.

`currentWindowStart` is derived as `resetTime5h - 5 hours` from the most recent snapshot. We do not try to detect the window start from history — the page reports `resetTime5h` directly, and that's the source of truth.

**Algorithm — weighted linear regression:**

```
points = snapshots where ts >= now - W*60  AND  ts >= currentWindowStart
x = (ts - now) seconds   (most recent point is x=0)
y = used_5h
weights = exp(x / 1800)      // exponential decay, 30min half-life
slope, intercept = weighted_least_squares(x, y, weights)
```

**Outputs:**
- `projectedHitTime` = `now + (ceiling_5h - used_5h) / slope` (clamped: if `slope ≤ 0` → "stable, no projection")
- `forecastLine` = points `(t, intercept + slope*(t-now))` from `t=now` to `t=min(projectedHitTime, currentWindowEnd)`
- `confidence` = R² of the regression. If `R² < 0.5`, line is dashed and labeled "low confidence."

**Edge cases:** < 3 points → no forecast; slope ≤ 0 → "stable" label; projection past window reset → clamp to "won't hit limit this window."

### 5.2 Long-term hour-of-day baseline (used on 24h / 1w charts)

**Goal:** show "what does my usage typically look like at this time?"

**Algorithm — per-hour rolling median:**

```
For each hour h ∈ [0..23]:
    samples = snapshots from last 14 days at hour h
              (weekday-matched for 1w chart, any-weekday for 24h chart)
    baseline[h] = median(used_5h / ceiling_5h)
    band[h]     = (P25, P75) of the same set
```

**Outputs:**
- `baselineCurve` = 24-point or 168-point curve drawn as a faint solid line.
- `band` = translucent ribbon between P25 and P75.
- `actualCurve` = today's real usage drawn on top.

**Edge cases:** < 3 days of history → don't draw baseline; show "Building baseline — need 3+ days of history."

### 5.3 What appears in the UI

- **1h / 8h:** actual (solid) + linear forecast (dashed). Caption `⏱ likely full at 14:23` (or `~14:23 (low confidence)` if `R² < 0.5`).
- **24h:** actual (solid) + baseline ribbon underneath. No forward forecast.
- **1w:** actual (solid) + baseline ribbon (weekday-matched). No forward forecast.

### 5.4 Explicit non-goals (math-side YAGNI)

- No ML model. Linear + percentiles only.
- No per-prompt prediction.
- No team usage estimation.
- **No cross-window combined forecast** (e.g. "you'll hit weekly cap by Friday"). The compounding assumptions (which 5h windows get used, at what rate) make the output too noisy to be trustworthy. Deliberately omitted.

## 6. macOS UI

### 6.1 Menu bar item

- `NSStatusItem`, variable-width title.
- Display format: `⌬ 47%` (icon + 5h percentage).
- Updates every poll (90s).
- Color: monochrome glyph follows system tint. Number turns **orange** at ≥75%, **red** at ≥90%. Setting "always use system color" disables warning tints.
- Click → toggle popover. Right-click → minimal menu (`About`, `Settings…`, `Sign out…`, `Quit`).
- Hover tooltip: `5h: 47% • Week: 23% • Resets in 2h 13m`.
- No-data states: `⌬ —` (never succeeded), `⌬ ⚠` (last poll failed).

### 6.2 Popover (`NSPopover`)

Width 340pt, height grows with content (~420pt typical).

```
┌─────────────────────────────────────────┐
│  CLAUDE USAGE             Pro           │
├─────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐    │
│  │ 5H           │  │ WEEK         │    │
│  │ 47%          │  │ 23%          │    │
│  │ ████░░░░░░   │  │ ██░░░░░░░░   │    │
│  │ resets 2h13m │  │ resets Sun   │    │
│  └──────────────┘  └──────────────┘    │
├─────────────────────────────────────────┤
│   [1h] (8h) (24h) (1w)                  │
│                                         │
│   [chart: history + dashed forecast]    │
│                                         │
│  ⏱ likely full at 14:23                 │
├─────────────────────────────────────────┤
│  Last poll: 47s ago • Refresh           │
└─────────────────────────────────────────┘
```

**Components**
- Header strip: `CLAUDE USAGE` + plan tier (right).
- Two gauge cards (label, %, progress bar with green/orange/red, reset countdown).
- Timeframe selector: SwiftUI `Picker(.segmented)`, four options, persisted in settings.
- Chart: Swift Charts. History as solid `LineMark`, forecast as dashed `LineMark` (1h/8h only), baseline ribbon as `AreaMark` (24h/1w only). Y-axis 0–100% of 5h ceiling. X-axis relative time labels.
- Forecast caption visible only when `projectedHitTime` is set and falls in the visible window.
- Footer: "Last poll: Ns ago" (green/orange/red by age) + "Refresh" (rate-limited 1× per 10s).

Popover dismissal: click outside, Escape, or click the menu bar icon again.

### 6.3 Settings window

Plain `NSWindow`, opened from right-click menu or popover ⚙ button.

- **Account:** "Signed in as `email@…`" + "Sign out" + "Re-login" button.
- **Plan tier:** read-only auto-detected, with "Override" toggle for forced ceiling.
- **Alerts:** toggles per § 8.
- **Polling:** read-only "Every 90s" (not user-configurable in v1).
- **Theme:** Auto / Light / Dark.
- **Data:** "Export history (CSV)" + "Delete all local + iCloud data" (with confirm).

### 6.4 First-run experience

1. Menu bar shows `⌬ ⏳`.
2. WKWebView opens (~500×700pt window) with claude.ai login.
3. After login redirect, window auto-closes; first poll fires; menu bar updates to `⌬ 47%`.
4. One-time popover tip: "Click the menu bar icon to see charts." Dismisses on first popover open.

## 7. iOS UI

### 7.1 First run

1. App launch → no Keychain cookie → full-screen WKWebView sheet with claude.ai login.
2. After login redirect, sheet dismisses; first poll fires.
3. Onboarding overlay (one tap to dismiss): three steps explaining gauges, charts/forecast, and "long-press home screen to add a widget."

### 7.2 Main screen — single vertical scroll

```
┌──────────────────────────────┐
│ Claude Usage          ⚙       │   nav bar
├──────────────────────────────┤
│ ┌──────────┐ ┌──────────┐    │
│ │ 5H 47%   │ │ WEEK 23% │    │   gauge cards
│ │ █████░░░ │ │ ██░░░░░░ │    │   (responsive: stacked or side-by-side)
│ │ 2h 13m   │ │ Sun      │    │
│ └──────────┘ └──────────┘    │
├──────────────────────────────┤
│  [1h] (8h) (24h) (1w)         │
│  [chart, same as Mac]         │
│  ⏱ likely full at 14:23       │
├──────────────────────────────┤
│ Recent activity              │
│ Last poll: 47s ago           │
│ Today's tokens: 312k         │
│ Peak hour today: 13:00       │
├──────────────────────────────┤
│ Devices syncing               │
│ • Mac (47s ago)              │
│ • iPhone (just now)          │
└──────────────────────────────┘
```

Pull-to-refresh forces an immediate poll (10s rate cap shared with Mac Refresh button).

### 7.3 Home-screen widgets

Three sizes, all reading directly from the App Group SQLite cache (no network).

- **Small (2×2):** `CLAUDE · 5H` label + big `47%` + mini progress bar + `2h 13m left`.
- **Medium (4×2):** both gauges + tiny 1h sparkline (with dashed forecast extension if available).
- **Large (4×4):** both gauges + larger 8h chart with timeframe label + forecast caption + `Updated Ns ago` footer.

**Refresh policy.** Widgets request `TimelineReload` after every successful main-app poll. Without app activity, iOS calls `getTimeline` ~every 15-30 min; we serve stale-but-fresh-looking data from SQLite, with the `Updated Ns ago` footer making staleness visible. The widget never polls itself.

### 7.4 Lock-screen widgets (iOS 16+)

- **`.accessoryCircular`:** ring gauge of the 5h percentage. Tap → app.
- **`.accessoryRectangular`:** `Claude · 5h 47% · 2h 13m left`.
- `.accessoryInline`: skipped (too narrow).

### 7.5 Settings (iOS sheet)

Same content as macOS Settings (§ 6.3): account, plan tier, alerts, theme, data export, sign out.

### 7.6 Explicitly skipped on iOS for v1

- Live Activities / Dynamic Island (no reliable "active session" signal).
- Apple Watch app.
- iPad-native layout (runs in iPhone-compat size class; v2 work).
- Shortcuts intents (v2).

## 8. Notifications & alerts

### 8.1 Alert types

| Kind | Trigger | Where |
|---|---|---|
| `5h-forecast` | `projectedHitTime` within next 15 min AND `R² ≥ 0.5` | Per-device, dedup'd per 5h window |
| `5h-hit` | `used_5h ≥ ceiling_5h` | Per-device, fires once per window |
| `week-90` | `used_week / ceiling_week ≥ 0.9` | Once per week |
| `week-100` | `used_week ≥ ceiling_week` | Once per week |
| `auth-expired` | 2 consecutive failed auth polls | Per-device, once per outage |
| `scrape-broken` | Both JSON and HTML scrapers failing for >30 min | Per-device, once per outage |

### 8.2 Suppression rules

- Per-window dedup: `5h-forecast` and `5h-hit` keyed by 5h window start `T`. Once fired for `T`, no further alerts of that kind until a new window starts.
- Hysteresis: `5h-forecast` does not re-fire within the same window even if rate dips and climbs again.
- Quiet hours: user-configurable (default 22:00 → 08:00). Alerts during quiet hours are queued and surfaced as a summary banner on next foreground; never as push.
- Snooze: swipe-to-snooze (iOS) / right-click "Snooze 1h" (Mac) → records `alert_state.snoozed_until`.

### 8.3 Delivery

- **macOS:** `UNUserNotificationCenter` (UserNotifications, macOS 11+). Banner style by default. Click → opens popover with the relevant chart.
- **iOS:** local `UNUserNotificationCenter` notifications. Two notification-category actions: `Snooze 1h`, `Open chart`. Background polling caveat: iOS may delay an `auth-expired` notification by up to 15 min on iOS — accepted.

### 8.4 Permission request

- **macOS:** request UN authorization lazily, the first time we'd want to fire an alert. Denied → fall back to in-app red badges only.
- **iOS:** request as part of onboarding overlay (§ 7.1), framed as "We'll only ping you when you're about to hit a limit." Skippable.

### 8.5 Math vs UX yagni

- No threshold alerts on 5h (we use forecast). User cannot add `5h-75%` etc.
- No weekly digests in v1.
- No custom alert sounds.
- No Focus integration beyond what iOS does for free.

## 9. Risks, non-goals, open questions

### 9.1 Risks

| Risk | Severity | Mitigation |
|---|---|---|
| Anthropic changes JSON endpoint shape | High | `sourceVersion` on snapshots; HTML scraper fallback; raw-payload retention; visible "source format changed" banner |
| Anthropic detects automation, rate-limits or suspends account | Medium | 90s cadence + ±10s jitter; exponential backoff on 429; matching User-Agent; never tight-loop |
| `cf_clearance` expires and silent refresh fails | Medium | Hidden WKWebView re-acquisition (§ 2.2); 2-retry then user banner; exponential backoff while broken |
| Untested plan tier (Team / Enterprise) | Medium | Plan read from page directly; unknown tier → "Custom" with manual ceiling; never hardcode |
| CloudKit quota exceeded / sync fails | Low | SQLite is source of truth; CloudKit best-effort; surface sync errors only after 24h failure |
| iCloud not signed in on iOS | Low | App still works locally with iPhone-only history; banner suggests iCloud sign-in |
| WKWebView cookies wiped (low memory) | Low | Auth-expired flow handles it; user re-logs in |
| User's claude.ai password / SSO changes | Low | Same auth-expired flow |
| Forecast misleads on bursty workloads | Low-medium | R² confidence, dashed-with-label for low-confidence, never persisted as predictions |

### 9.2 Non-goals

- Anthropic API monitoring (this app is for claude.ai / Claude Code product limits only).
- Multi-account support.
- Team / Org views.
- Cost forecasting in dollars.
- Cross-window combined forecast (§ 5.4).
- Live Activities / Dynamic Island (§ 7.6).
- Apple Watch / iPad-native / Shortcuts intents (§ 7.6).
- Windows / Linux (precluded by native SwiftUI choice).
- Sub-90s "live" updates.
- Public sharing or leaderboards.

### 9.3 Open questions to resolve during implementation

1. **Actual JSON endpoint URL** — discovered in implementation step 1 by inspecting DevTools on `/settings/usage`.
2. **Plan tier strings** — confirm exact spellings (`"Pro"`, `"Max 5x"`, `"Max 20x"`, `"Team"`, `"Free"`).
3. **Anthropic session-cookie HttpOnly status** — almost certainly readable from `WKWebsiteDataStore.httpCookieStore`; verify before relying on it.
4. **5h window reset semantics** — calendar-aligned, rolling-from-first-message, or rolling-from-each-message? Confirm by observation.
5. **CloudKit container name** — needs Apple Developer account configured before any CloudKit code runs.

### 9.4 Success criteria (v1)

- Mac menu bar shows current 5h % and updates within 90s of usage changes.
- iPhone widget shows the same data within 5 min of an iPhone-side poll.
- Charts render in <100ms from local cache.
- Forecast caption appears with `R² ≥ 0.5` and is hidden otherwise.
- Auth recovery completes in <30s when a session expires.
- Zero crashes in a 24h soak test on each platform.
- Poll failure rate <1% in normal operation (excluding Anthropic outages).

## 10. Decision log (brainstorming summary)

| # | Decision | Choice |
|---|---|---|
| 1 | Platform | macOS primary + iOS companion, share via iCloud |
| 2 | Data source | Scrape `claude.ai/settings/usage` (JSON intercept preferred, HTML fallback) |
| 3 | Scope | Full feature set on both platforms in v1 |
| 4 | Menu bar style | Number only: `⌬ 47%` |
| 5 | macOS click target | Compact popover only (no separate full window) |
| 6 | iOS shape | Full app + home-screen widgets + lock-screen widgets (no Live Activities in v1) |
| 7 | Forecast | Both: short-term linear (1h/8h) + hour-of-day baseline (24h/1w) |
| 8 | Alerts | Forecast-based for 5h, threshold-based for weekly |
| 9 | Auth flow | Each device logs in independently; no cookie sharing |
| 10 | Polling cadence | 90 seconds (± 10s jitter) |
| 11 | ToS gray-area | Accepted by user for own account |
| 12 | Architecture | Native SwiftUI shared package; not Electron / Tauri / cross-platform |
