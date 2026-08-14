# Fable Weekly Quota + Popover Auto-Hide Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the Fable per-model weekly quota as a third gauge card in the popover, and make the popover dismiss itself on outside click or after 10 idle seconds.

**Architecture:** Data flows bottom-up through the existing layers — `JSONUsageScraper` learns to read Anthropic's new `limits[]` array, `UsageSnapshot` carries three new optional fields, SQLite migration `v2` persists them, and `PopoverRootView` conditionally renders a third `GaugeCardView`. The popover dismissal work is unrelated to the data path and lives entirely in `PopoverController`.

**Tech Stack:** Swift 5.10, SwiftUI, AppKit (`NSPopover`, `NSEvent` global monitor, `Timer`), GRDB.swift (SQLite), XCTest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-08-13-fable-quota-and-popover-autohide-design.md`

## Global Constraints

- **`project.yml` is the source of truth for the Xcode project.** Never edit `ClaudeWatch.xcodeproj` directly. After adding or removing any file under `Apps/`, run `xcodegen generate`.
- **Percent scale is 0–10000.** Anthropic reports `utilization` / `percent` as 0–100; every usage number stored in `UsageSnapshot` is `Int((value * 100).rounded())` against a ceiling of `10_000`. Fable follows the same convention.
- **`limits` must decode as optional.** An API response without the `limits` key must produce a valid snapshot, not `ScrapeError.schemaDrift`.
- **`nil` Fable means "this account has no Fable limit"** — every UI surface hides the card rather than showing a zero.
- **All 8 locales stay in sync:** `en`, `zh-Hans`, `zh-Hant`, `ja`, `ko`, `es`, `de`, `fr`. A new key added to one must be added to all.
- **Swift package tests run from the package root:** `cd Packages/UsageCore && swift test`. The macOS app builds with `xcodebuild -project ClaudeWatch.xcodeproj -scheme ClaudeWatchMac -configuration Debug -destination 'platform=macOS' build`.
- **Branch:** `main`. The user has confirmed direct main work for this project.

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `Packages/UsageCore/Sources/UsageCore/Models/UsageSnapshot.swift` | Carries the three Fable fields + `fractionFable` | 1 |
| `Packages/UsageCore/Sources/UsageCore/Scraping/JSONUsageScraper.swift` | Decodes `limits[]`, extracts the Fable entry | 1 |
| `Packages/UsageCore/Tests/UsageCoreTests/Scraping/JSONUsageScraperTests.swift` | 4 parsing cases | 1 |
| `Packages/UsageCore/Sources/UsageCore/Storage/Database.swift` | Migration `v2` — 3 nullable columns | 2 |
| `Packages/UsageCore/Sources/UsageCore/Storage/SnapshotRepository.swift` | Writes/reads the 3 columns | 2 |
| `Packages/UsageCore/Tests/UsageCoreTests/Storage/SnapshotRepositoryTests.swift` | Round-trip + legacy-row cases | 2 |
| `Apps/ClaudeWatchMac/Popover/LineChartView.swift` | `ChartPalette.actualFable` (purple) | 3 |
| `Apps/ClaudeWatchMac/Popover/GaugeCardView.swift` | `isActive` border parameter | 3 |
| `Apps/ClaudeWatchMac/Popover/PopoverRootView.swift` | Conditional third card, compact captions | 3 |
| `Apps/ClaudeWatchMac/Resources/*.lproj/Localizable.strings` × 8 | `popover.gauge.fable`, shortened captions | 3 |
| `Apps/ClaudeWatchMac/Popover/PopoverController.swift` | Global event monitor + idle timer | 4 |

Tasks 1–3 form the Fable feature bottom-up; each leaves the build green. Task 4 is independent and could be done first — it is last only because the user's primary ask was Fable.

---

## Task 1: Parse the Fable limit from `limits[]`

**Files:**
- Modify: `Packages/UsageCore/Sources/UsageCore/Models/UsageSnapshot.swift`
- Modify: `Packages/UsageCore/Sources/UsageCore/Scraping/JSONUsageScraper.swift`
- Test: `Packages/UsageCore/Tests/UsageCoreTests/Scraping/JSONUsageScraperTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `UsageSnapshot.usedFable: Int?` — 0–10000 scale, `nil` when the account has no Fable limit
  - `UsageSnapshot.resetTimeFable: Date?`
  - `UsageSnapshot.fableIsActive: Bool` — non-optional, `false` when absent
  - `UsageSnapshot.fractionFable: Double?` — `usedFable / 10_000`, `nil` when `usedFable` is `nil`
  - `UsageSnapshot.init` gains three trailing parameters defaulted to `nil, nil, false`, so every existing call site keeps compiling unchanged.

- [ ] **Step 1: Add the three fields to `UsageSnapshot`**

In `Packages/UsageCore/Sources/UsageCore/Models/UsageSnapshot.swift`, replace the whole struct body's stored-property block, initializer, and add the new computed property. The file becomes:

```swift
import Foundation

public struct UsageSnapshot: Equatable, Codable {
    public let timestamp: Date
    public let plan: Plan
    public let used5h: Int
    public let ceiling5h: Int
    public let resetTime5h: Date
    public let usedWeek: Int
    public let ceilingWeek: Int
    public let resetTimeWeek: Date
    public let sourceVersion: String
    public let raw: Data

    /// Fable is a per-model *weekly* limit Anthropic reports in the
    /// `limits[]` array as `kind == "weekly_scoped"`. Not every account
    /// has one, so all three fields degrade to nil/false rather than
    /// zero — the UI hides the gauge entirely when `usedFable` is nil,
    /// which is meaningfully different from "you have a Fable limit and
    /// have used 0% of it".
    ///
    /// Same 0–10000 scale as `used5h` / `usedWeek` (percent × 100), so
    /// the shared ceiling of 10_000 applies.
    public let usedFable: Int?
    public let resetTimeFable: Date?
    /// Anthropic's `is_active` flag: true when this is the limit
    /// currently throttling the account. Surfaced so the UI can point
    /// at the gauge that actually matters.
    public let fableIsActive: Bool

    public init(timestamp: Date, plan: Plan,
                used5h: Int, ceiling5h: Int, resetTime5h: Date,
                usedWeek: Int, ceilingWeek: Int, resetTimeWeek: Date,
                sourceVersion: String, raw: Data,
                usedFable: Int? = nil,
                resetTimeFable: Date? = nil,
                fableIsActive: Bool = false) {
        self.timestamp = timestamp
        self.plan = plan
        self.used5h = used5h; self.ceiling5h = ceiling5h; self.resetTime5h = resetTime5h
        self.usedWeek = usedWeek; self.ceilingWeek = ceilingWeek; self.resetTimeWeek = resetTimeWeek
        self.sourceVersion = sourceVersion
        self.raw = raw
        self.usedFable = usedFable
        self.resetTimeFable = resetTimeFable
        self.fableIsActive = fableIsActive
    }

    public var fraction5h: Double {
        guard ceiling5h > 0 else { return 0 }
        return min(1.0, Double(used5h) / Double(ceiling5h))
    }
    public var fractionWeek: Double {
        guard ceilingWeek > 0 else { return 0 }
        return min(1.0, Double(usedWeek) / Double(ceilingWeek))
    }
    /// nil when the account has no Fable limit — callers use that to
    /// decide whether to render the Fable gauge at all.
    public var fractionFable: Double? {
        guard let u = usedFable else { return nil }
        return min(1.0, Double(u) / 10_000)
    }
    public var currentWindowStart5h: Date {
        resetTime5h.addingTimeInterval(-5 * 3600)
    }
}
```

- [ ] **Step 2: Append the four failing tests**

Append these four methods inside the existing `final class JSONUsageScraperTests: XCTestCase { ... }` in `Packages/UsageCore/Tests/UsageCoreTests/Scraping/JSONUsageScraperTests.swift`, just before the class's closing brace. Do not modify the existing tests.

```swift
    // MARK: - limits[] / Fable parsing

    /// Builds a scraper wired to URLProtocolMock for the given JSON body.
    /// Each test uses a distinct URL so the shared `responses` dictionary
    /// can't leak state between tests.
    private func makeScraper(url: String, body: String) -> JSONUsageScraper {
        let u = URL(string: url)!
        URLProtocolMock.responses[u] = (200, body.data(using: .utf8)!)
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [URLProtocolMock.self]
        return JSONUsageScraper(
            endpoint: u,
            cookies: CookiePackage(sessionKey: "s", cfClearance: nil, cfBm: nil,
                                   userAgent: "UA", all: []),
            session: URLSession(configuration: cfg))
    }

    func test_limits_withFable_extractsUtilizationAndReset() async throws {
        // Real shape observed 2026-08-13. The Fable limit is the
        // weekly_scoped entry; is_active marks it as the binding one.
        let body = """
        {
            "five_hour": { "utilization": 26.0, "resets_at": "2026-08-13T15:09:59.783360+00:00" },
            "seven_day": { "utilization": 69.0, "resets_at": "2026-08-13T21:00:00.783384+00:00" },
            "limits": [
                { "kind": "session", "group": "session", "percent": 26,
                  "severity": "normal", "resets_at": "2026-08-13T15:09:59.783360+00:00",
                  "scope": null, "is_active": false },
                { "kind": "weekly_all", "group": "weekly", "percent": 69,
                  "severity": "normal", "resets_at": "2026-08-13T21:00:00.783384+00:00",
                  "scope": null, "is_active": false },
                { "kind": "weekly_scoped", "group": "weekly", "percent": 99,
                  "severity": "critical", "resets_at": "2026-08-13T20:59:59.783618+00:00",
                  "scope": { "model": { "id": null, "display_name": "Fable" }, "surface": null },
                  "is_active": true }
            ]
        }
        """
        let scraper = makeScraper(url: "https://claude.ai/api/fable-present", body: body)
        let snap = try await scraper.fetchSnapshot()
        XCTAssertEqual(snap.usedFable, 9900)          // 99 × 100
        XCTAssertEqual(snap.fractionFable ?? 0, 0.99, accuracy: 0.0001)
        XCTAssertTrue(snap.fableIsActive)
        XCTAssertNotNil(snap.resetTimeFable)
        // Legacy top-level fields must still parse.
        XCTAssertEqual(snap.used5h, 2600)
        XCTAssertEqual(snap.usedWeek, 6900)
    }

    func test_limits_withoutFable_yieldsNilFable() async throws {
        let body = """
        {
            "five_hour": { "utilization": 26.0, "resets_at": "2026-08-13T15:09:59.783360+00:00" },
            "seven_day": { "utilization": 69.0, "resets_at": "2026-08-13T21:00:00.783384+00:00" },
            "limits": [
                { "kind": "session", "group": "session", "percent": 26,
                  "severity": "normal", "resets_at": "2026-08-13T15:09:59.783360+00:00",
                  "scope": null, "is_active": false },
                { "kind": "weekly_all", "group": "weekly", "percent": 69,
                  "severity": "normal", "resets_at": "2026-08-13T21:00:00.783384+00:00",
                  "scope": null, "is_active": false }
            ]
        }
        """
        let scraper = makeScraper(url: "https://claude.ai/api/fable-absent", body: body)
        let snap = try await scraper.fetchSnapshot()
        XCTAssertNil(snap.usedFable)
        XCTAssertNil(snap.fractionFable)
        XCTAssertNil(snap.resetTimeFable)
        XCTAssertFalse(snap.fableIsActive)
    }

    func test_limitsFieldAbsent_doesNotThrowSchemaDrift() async throws {
        // The pre-2026-08 response shape. Must still decode.
        let body = """
        {
            "five_hour": { "utilization": 3.0, "resets_at": "2026-04-30T19:09:59.955046+00:00" },
            "seven_day": { "utilization": 59.0, "resets_at": "2026-04-30T20:59:59.955071+00:00" },
            "seven_day_opus": null,
            "extra_usage": { "is_enabled": false }
        }
        """
        let scraper = makeScraper(url: "https://claude.ai/api/no-limits-key", body: body)
        let snap = try await scraper.fetchSnapshot()
        XCTAssertEqual(snap.used5h, 300)
        XCTAssertEqual(snap.usedWeek, 5900)
        XCTAssertNil(snap.usedFable)
        XCTAssertFalse(snap.fableIsActive)
    }

    func test_limits_scopedButDifferentModel_yieldsNilFable() async throws {
        // Guards against matching on `kind` alone: a future Opus weekly
        // limit must not be mistaken for Fable.
        let body = """
        {
            "five_hour": { "utilization": 26.0, "resets_at": "2026-08-13T15:09:59.783360+00:00" },
            "seven_day": { "utilization": 69.0, "resets_at": "2026-08-13T21:00:00.783384+00:00" },
            "limits": [
                { "kind": "weekly_scoped", "group": "weekly", "percent": 42,
                  "severity": "normal", "resets_at": "2026-08-13T20:59:59.783618+00:00",
                  "scope": { "model": { "id": null, "display_name": "Opus" }, "surface": null },
                  "is_active": true }
            ]
        }
        """
        let scraper = makeScraper(url: "https://claude.ai/api/scoped-opus", body: body)
        let snap = try await scraper.fetchSnapshot()
        XCTAssertNil(snap.usedFable)
        XCTAssertFalse(snap.fableIsActive)
    }
```

- [ ] **Step 3: Run the new tests to verify they fail**

```bash
cd Packages/UsageCore && swift test --filter JSONUsageScraperTests 2>&1 | tail -20
```

Expected: the three Fable-specific tests FAIL on assertions (`usedFable` is always `nil` because nothing populates it yet). `test_limitsFieldAbsent_doesNotThrowSchemaDrift` may already pass — that is fine, it is a regression guard.

- [ ] **Step 4: Decode `limits[]` and extract Fable**

In `Packages/UsageCore/Sources/UsageCore/Scraping/JSONUsageScraper.swift`, replace the private `Response` struct:

```swift
    private struct Response: Decodable {
        let five_hour: Window?
        let seven_day: Window?
        /// Added by Anthropic around 2026-08. Optional so a response
        /// from an older or regional deployment that lacks the key
        /// decodes cleanly instead of tripping schemaDrift.
        let limits: [Limit]?

        struct Window: Decodable {
            let utilization: Double
            let resets_at: Date?
        }

        /// One entry of the `limits[]` array. Every field is optional
        /// because Anthropic adds fields to this shape frequently and
        /// we only care about four of them.
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

    /// Display name Anthropic uses for the Fable model in
    /// `limits[].scope.model.display_name`. Matched exactly — if
    /// Anthropic renames it, the Fable gauge disappears rather than
    /// showing another model's numbers.
    private static let fableDisplayName = "Fable"
```

Then, inside `fetchSnapshot()`, in the `do { ... }` block that decodes and builds the snapshot, insert the extraction after `let usedWeek = ...` and pass the three new arguments to `UsageSnapshot(...)`. The block becomes:

```swift
        do {
            let r = try dec.decode(Response.self, from: data)
            let now = Date()
            let used5h = Int(((r.five_hour?.utilization ?? 0) * 100).rounded())
            let usedWeek = Int(((r.seven_day?.utilization ?? 0) * 100).rounded())

            // Fable is a per-model weekly limit. Match on BOTH the kind
            // and the model display name — matching kind alone would
            // pick up any future scoped limit (Opus, Cowork, …) and
            // label it Fable.
            let fable = r.limits?.first {
                $0.kind == "weekly_scoped"
                    && $0.scope?.model?.display_name == Self.fableDisplayName
            }
            let usedFable = fable?.percent.map { Int(($0 * 100).rounded()) }

            return UsageSnapshot(
                timestamp: now,
                // The /usage endpoint doesn't include the plan tier;
                // we surface "—" until/unless we wire a separate
                // /api/account or /api/organizations/{id} call.
                plan: .custom("—"),
                used5h: used5h,
                ceiling5h: 10_000,        // 100.00% scaled by 100
                resetTime5h: r.five_hour?.resets_at ?? now.addingTimeInterval(5 * 3600),
                usedWeek: usedWeek,
                ceilingWeek: 10_000,
                resetTimeWeek: r.seven_day?.resets_at ?? now.addingTimeInterval(7 * 86400),
                sourceVersion: sourceVersion,
                raw: data,
                usedFable: usedFable,
                resetTimeFable: fable?.resets_at,
                fableIsActive: fable?.is_active ?? false)
        } catch {
            throw ScrapeError.schemaDrift(version: sourceVersion, payload: data)
        }
```

Also update the doc comment above `Response` — the old one says the per-model windows are ignored, which is no longer true. Replace it with:

```swift
    /// Real shape of `claude.ai/api/organizations/{org_id}/usage`
    /// (observed 2026-04-30, extended 2026-08-13). Anthropic exposes
    /// utilization as a percentage (0–100) rather than raw token
    /// counts. We fold that into our snapshot's `used / ceiling` model
    /// by setting ceiling = 10000 and storing
    /// `used = round(utilization * 100)` so 0.01% of precision is kept.
    ///
    /// The 2026-08 revision added a `limits[]` array that supersedes
    /// the legacy per-model codename fields (`seven_day_opus`,
    /// `nimbus_quill`, `tangelo`, …) — those are now null even for
    /// accounts that do have per-model limits. We read the Fable
    /// weekly limit out of `limits[]`; the codename fields, `spend`,
    /// and `extra_usage` remain ignored.
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
cd Packages/UsageCore && swift test --filter JSONUsageScraperTests 2>&1 | tail -10
```

Expected: PASS, all tests in the suite.

- [ ] **Step 6: Run the full package suite to check nothing regressed**

```bash
cd Packages/UsageCore && swift test 2>&1 | tail -6
```

Expected: `Executed N tests, with 0 failures` where N is the previous count plus 4.

- [ ] **Step 7: Commit**

```bash
git add Packages/UsageCore/Sources/UsageCore/Models/UsageSnapshot.swift \
        Packages/UsageCore/Sources/UsageCore/Scraping/JSONUsageScraper.swift \
        Packages/UsageCore/Tests/UsageCoreTests/Scraping/JSONUsageScraperTests.swift
git commit -m "$(cat <<'EOF'
feat(core): parse the Fable weekly limit from the new limits[] array

Anthropic's /usage endpoint grew a `limits[]` array around 2026-08
carrying per-model weekly quotas. It supersedes the legacy codename
fields (seven_day_opus, nimbus_quill, tangelo, ...) which now return
null even for accounts that do have per-model limits.

UsageSnapshot gains usedFable / resetTimeFable / fableIsActive. All
three are optional-or-defaulted so every existing initializer call
site compiles unchanged, and nil means "this account has no Fable
limit" — meaningfully different from "has one, used 0%".

The Fable entry is matched on BOTH kind == "weekly_scoped" AND
scope.model.display_name == "Fable". Matching kind alone would
mislabel any future scoped limit (Opus, Cowork) as Fable; a test
covers exactly that case.

`limits` decodes as optional so a response predating the change
still yields a snapshot instead of ScrapeError.schemaDrift.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Persist the Fable fields (migration `v2`)

**Files:**
- Modify: `Packages/UsageCore/Sources/UsageCore/Storage/Database.swift`
- Modify: `Packages/UsageCore/Sources/UsageCore/Storage/SnapshotRepository.swift`
- Test: `Packages/UsageCore/Tests/UsageCoreTests/Storage/SnapshotRepositoryTests.swift`

**Interfaces:**
- Consumes: `UsageSnapshot.usedFable` / `.resetTimeFable` / `.fableIsActive` from Task 1.
- Produces: snapshots round-tripped through SQLite retain all three Fable fields. Rows written before this migration read back with `usedFable == nil`, `resetTimeFable == nil`, `fableIsActive == false`.

- [ ] **Step 1: Write the two failing tests**

Append these two methods inside the existing `final class SnapshotRepositoryTests: XCTestCase { ... }` in `Packages/UsageCore/Tests/UsageCoreTests/Storage/SnapshotRepositoryTests.swift`, before the closing brace.

```swift
    func test_insertAndFetch_roundTripsFableFields() throws {
        let repo = SnapshotRepository(dbq: dbq, deviceID: "dev")
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let fableReset = Date(timeIntervalSince1970: 1_770_050_000)
        let snap = UsageSnapshot(
            timestamp: now, plan: .pro,
            used5h: 2600, ceiling5h: 10_000, resetTime5h: now.addingTimeInterval(3600),
            usedWeek: 6900, ceilingWeek: 10_000, resetTimeWeek: now.addingTimeInterval(86_400),
            sourceVersion: "json-v2", raw: Data(),
            usedFable: 9900, resetTimeFable: fableReset, fableIsActive: true)
        try repo.insert(snap)

        let got = try repo.mostRecent()
        XCTAssertEqual(got?.usedFable, 9900)
        XCTAssertEqual(got?.resetTimeFable?.timeIntervalSince1970,
                       fableReset.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(got?.fableIsActive, true)
    }

    func test_insertWithoutFable_readsBackAsNil() throws {
        // Mirrors both a Fable-less account AND any row written by a
        // build predating migration v2.
        let repo = SnapshotRepository(dbq: dbq, deviceID: "dev")
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let snap = UsageSnapshot(
            timestamp: now, plan: .pro,
            used5h: 2600, ceiling5h: 10_000, resetTime5h: now.addingTimeInterval(3600),
            usedWeek: 6900, ceilingWeek: 10_000, resetTimeWeek: now.addingTimeInterval(86_400),
            sourceVersion: "json-v2", raw: Data())
        try repo.insert(snap)

        let got = try repo.mostRecent()
        XCTAssertNotNil(got)
        XCTAssertNil(got?.usedFable)
        XCTAssertNil(got?.resetTimeFable)
        XCTAssertEqual(got?.fableIsActive, false)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd Packages/UsageCore && swift test --filter SnapshotRepositoryTests 2>&1 | tail -20
```

Expected: `test_insertAndFetch_roundTripsFableFields` FAILS (`usedFable` comes back `nil` because the column does not exist and `insert` does not write it). The `test_insertWithoutFable_readsBackAsNil` case may already pass.

- [ ] **Step 3: Add migration `v2`**

In `Packages/UsageCore/Sources/UsageCore/Storage/Database.swift`, insert a second migration registration immediately after the closing `}` of the `m.registerMigration("v1") { ... }` block and before `return m`:

```swift
        // Fable is a per-model weekly quota Anthropic began reporting
        // in 2026-08. Nullable because not every account has one, and
        // because every row written before this migration genuinely
        // has no value — defaulting to 0 would render as "0% used"
        // instead of "no such limit".
        //
        // snapshots_5min is deliberately NOT extended: that rollup
        // table feeds long-range chart aggregation and we don't chart
        // Fable.
        m.registerMigration("v2") { db in
            try db.execute(sql: """
                ALTER TABLE snapshots ADD COLUMN used_fable INTEGER;
                ALTER TABLE snapshots ADD COLUMN reset_fable INTEGER;
                ALTER TABLE snapshots ADD COLUMN fable_is_active INTEGER NOT NULL DEFAULT 0;
            """)
        }
```

- [ ] **Step 4: Write and read the new columns**

In `Packages/UsageCore/Sources/UsageCore/Storage/SnapshotRepository.swift`, replace the `insert` method:

```swift
    public func insert(_ s: UsageSnapshot) throws {
        try dbq.write { db in
            try db.execute(sql: """
                INSERT INTO snapshots
                (device_id, ts, plan, used_5h, ceiling_5h, reset_5h,
                 used_week, ceiling_week, reset_week, source_version, synced_to_cloud,
                 used_fable, reset_fable, fable_is_active)
                VALUES (?,?,?,?,?,?,?,?,?,?,0,?,?,?)
            """, arguments: [
                deviceID, Int(s.timestamp.timeIntervalSince1970), s.plan.displayName,
                s.used5h, s.ceiling5h, Int(s.resetTime5h.timeIntervalSince1970),
                s.usedWeek, s.ceilingWeek, Int(s.resetTimeWeek.timeIntervalSince1970),
                s.sourceVersion,
                s.usedFable,
                s.resetTimeFable.map { Int($0.timeIntervalSince1970) },
                s.fableIsActive
            ])
        }
    }
```

and replace `fromRow`:

```swift
    private static func fromRow(_ r: Row) -> UsageSnapshot {
        // Rows written before migration v2 have NULL in the three
        // fable columns; GRDB's optional subscript yields nil, which
        // is exactly what "this account has no Fable limit" means to
        // every consumer.
        let resetFable: Date? = (r["reset_fable"] as Int?)
            .map { Date(timeIntervalSince1970: TimeInterval($0)) }
        return UsageSnapshot(
            timestamp: Date(timeIntervalSince1970: r["ts"]),
            plan: Plan(rawString: r["plan"]),
            used5h: r["used_5h"], ceiling5h: r["ceiling_5h"],
            resetTime5h: Date(timeIntervalSince1970: r["reset_5h"]),
            usedWeek: r["used_week"], ceilingWeek: r["ceiling_week"],
            resetTimeWeek: Date(timeIntervalSince1970: r["reset_week"]),
            sourceVersion: r["source_version"],
            raw: Data(),
            usedFable: r["used_fable"],
            resetTimeFable: resetFable,
            fableIsActive: r["fable_is_active"] ?? false
        )
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
cd Packages/UsageCore && swift test --filter SnapshotRepositoryTests 2>&1 | tail -10
```

Expected: PASS.

- [ ] **Step 6: Run the full package suite**

```bash
cd Packages/UsageCore && swift test 2>&1 | tail -6
```

Expected: `Executed N tests, with 0 failures`.

- [ ] **Step 7: Verify the migration applies to the real on-disk database**

The developer's live database was created under `v1` and holds ~months of real rows. The unit tests run against a fresh in-memory database, so they never exercise the `v1 → v2` upgrade path on populated data. Run the migration's SQL against a copy of the real file and confirm nothing is lost:

```bash
cd /Users/shu/workspace/myportfolio/claude.usage
cp "$HOME/Library/Application Support/ClaudeWatch/usage.db" /tmp/usage-migration-check.db

echo "rows before: $(sqlite3 /tmp/usage-migration-check.db 'SELECT COUNT(*) FROM snapshots;')"

sqlite3 /tmp/usage-migration-check.db \
  "ALTER TABLE snapshots ADD COLUMN used_fable INTEGER;
   ALTER TABLE snapshots ADD COLUMN reset_fable INTEGER;
   ALTER TABLE snapshots ADD COLUMN fable_is_active INTEGER NOT NULL DEFAULT 0;"

echo "rows after:  $(sqlite3 /tmp/usage-migration-check.db 'SELECT COUNT(*) FROM snapshots;')"
echo "non-null fable: $(sqlite3 /tmp/usage-migration-check.db 'SELECT COUNT(*) FROM snapshots WHERE used_fable IS NOT NULL;')"

rm /tmp/usage-migration-check.db
```

Expected: `rows after` equals `rows before`, and `non-null fable` is `0` — every pre-existing row keeps its data and reads back as "no Fable limit".

If the `ALTER TABLE` statements error, the migration SQL is wrong and must be fixed before committing; do not let a broken migration reach the developer's real database, which is the only copy of their usage history.

- [ ] **Step 8: Commit**

```bash
git add Packages/UsageCore/Sources/UsageCore/Storage/Database.swift \
        Packages/UsageCore/Sources/UsageCore/Storage/SnapshotRepository.swift \
        Packages/UsageCore/Tests/UsageCoreTests/Storage/SnapshotRepositoryTests.swift
git commit -m "$(cat <<'EOF'
feat(core): persist Fable quota fields (migration v2)

Three nullable columns on `snapshots`: used_fable, reset_fable,
fable_is_active. Nullable rather than DEFAULT 0 because every row
written before this migration genuinely has no Fable reading —
storing 0 would render as "0% of your Fable quota used" instead of
"this account has no Fable quota", which is the distinction the
gauge card keys off.

snapshots_5min is deliberately left alone. That rollup table exists
to feed long-range chart aggregation and Fable isn't charted.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Third gauge card in the popover

**Files:**
- Modify: `Apps/ClaudeWatchMac/Popover/LineChartView.swift` (the `ChartPalette` enum near the top)
- Modify: `Apps/ClaudeWatchMac/Popover/GaugeCardView.swift`
- Modify: `Apps/ClaudeWatchMac/Popover/PopoverRootView.swift`
- Modify: `Apps/ClaudeWatchMac/Resources/{en,zh-Hans,zh-Hant,ja,ko,es,de,fr}.lproj/Localizable.strings`

**Interfaces:**
- Consumes: `UsageSnapshot.fractionFable: Double?`, `.resetTimeFable: Date?`, `.fableIsActive: Bool` from Task 1.
- Produces: `GaugeCardView(label:percent:resetCaption:tint:isActive:)` — `isActive` defaults to `false` so existing call sites compile; `ChartPalette.actualFable: Color`.

- [ ] **Step 1: Add the Fable tint to `ChartPalette`**

In `Apps/ClaudeWatchMac/Popover/LineChartView.swift`, find the `ChartPalette` enum near the top of the file and add one case alongside `actual5h` / `actualWeek`:

```swift
    /// Fable's identity color. Green (5h) and teal (week) are taken;
    /// purple stays legible in both light and dark popovers and
    /// carries no Anthropic brand association. Used only on the gauge
    /// card — Fable is not plotted on the chart.
    static let actualFable = Color.purple
```

- [ ] **Step 2: Add the `isActive` border to `GaugeCardView`**

In `Apps/ClaudeWatchMac/Popover/GaugeCardView.swift`, add the stored property after `tint` and replace the `.background(...)` modifier.

Add after `let tint: Color`:

```swift
    /// Anthropic's `is_active` flag for this limit — true when this is
    /// the quota currently throttling the account. Drawn as a 1 pt
    /// border because the danger colouring alone doesn't say it: a
    /// scoped limit at 99% blocks one model, not the whole account,
    /// and the user needs to know which gauge is the live constraint.
    var isActive: Bool = false
```

Replace:

```swift
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.1))
        )
```

with:

```swift
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isActive ? tint : Color.clear, lineWidth: 1)
        )
```

- [ ] **Step 3: Shorten the reset captions in all 8 locales**

Three cards at 98.7 pt leave 78.7 pt of inner width; the current captions overflow. Replace the two lines in each file.

`Apps/ClaudeWatchMac/Resources/en.lproj/Localizable.strings`:

```
"popover.reset.resetsIn %lld %lld" = "%lldh%lldm";
"popover.reset.resetsOn %@" = "%@";
```

`zh-Hans.lproj`:

```
"popover.reset.resetsIn %lld %lld" = "%lld时%lld分";
"popover.reset.resetsOn %@" = "%@";
```

`zh-Hant.lproj`:

```
"popover.reset.resetsIn %lld %lld" = "%lld時%lld分";
"popover.reset.resetsOn %@" = "%@";
```

`ja.lproj`:

```
"popover.reset.resetsIn %lld %lld" = "%lld時間%lld分";
"popover.reset.resetsOn %@" = "%@";
```

`ko.lproj`:

```
"popover.reset.resetsIn %lld %lld" = "%lld시간 %lld분";
"popover.reset.resetsOn %@" = "%@";
```

`es.lproj`:

```
"popover.reset.resetsIn %lld %lld" = "%lldh%lldm";
"popover.reset.resetsOn %@" = "%@";
```

`de.lproj`:

```
"popover.reset.resetsIn %lld %lld" = "%lldh%lldm";
"popover.reset.resetsOn %@" = "%@";
```

`fr.lproj`:

```
"popover.reset.resetsIn %lld %lld" = "%lldh%lldm";
"popover.reset.resetsOn %@" = "%@";
```

- [ ] **Step 4: Add the Fable gauge label in all 8 locales**

Add this line directly after the `"popover.gauge.week"` line in each of the 8 files. "Fable" is a product name and stays untranslated in every locale:

```
"popover.gauge.fable" = "Fable";
```

- [ ] **Step 5: Render the third card**

In `Apps/ClaudeWatchMac/Popover/PopoverRootView.swift`, replace the `HStack(spacing: 10) { ... }` block that holds the two gauge cards:

```swift
            HStack(spacing: 10) {
                // Tints mirror the chart line colors so the gauge cards
                // double as an implicit chart legend: green "5H" + green
                // fill ↔ green line; teal "WEEK" + teal fill ↔ teal line.
                // Danger is encoded separately in the percentage number
                // (yellow ≥ 75%, red ≥ 90%) — see GaugeCardView.
                //
                // Fable is a per-model weekly quota that only some
                // accounts have. When absent, the card is omitted and
                // the other two expand back to full width on their own
                // (each card is frame(maxWidth: .infinity)).
                GaugeCardView(label: String(localized: "popover.gauge.5h", defaultValue: "5h"),
                    percent: controller.state.latest?.fraction5h ?? 0,
                    resetCaption: resetCaption(controller.state.latest?.resetTime5h),
                    tint: ChartPalette.actual5h)
                GaugeCardView(label: String(localized: "popover.gauge.week", defaultValue: "Week"),
                    percent: controller.state.latest?.fractionWeek ?? 0,
                    resetCaption: weeklyResetCaption(controller.state.latest?.resetTimeWeek),
                    tint: ChartPalette.actualWeek)
                if let fable = controller.state.latest?.fractionFable {
                    GaugeCardView(label: String(localized: "popover.gauge.fable", defaultValue: "Fable"),
                        percent: fable,
                        resetCaption: weeklyResetCaption(controller.state.latest?.resetTimeFable),
                        tint: ChartPalette.actualFable,
                        isActive: controller.state.latest?.fableIsActive ?? false)
                }
            }
```

- [ ] **Step 6: Regenerate the project and build**

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

- [ ] **Step 7: Verify no localization key was missed**

```bash
for l in en zh-Hans zh-Hant ja ko es de fr; do
  printf "%-8s " "$l"
  grep -c '"popover.gauge.fable"' "Apps/ClaudeWatchMac/Resources/$l.lproj/Localizable.strings"
done
```

Expected: every line prints `1`. If any prints `0`, add the missing key before committing.

- [ ] **Step 8: Commit**

```bash
git add Apps/ClaudeWatchMac/Popover/LineChartView.swift \
        Apps/ClaudeWatchMac/Popover/GaugeCardView.swift \
        Apps/ClaudeWatchMac/Popover/PopoverRootView.swift \
        Apps/ClaudeWatchMac/Resources/*.lproj/Localizable.strings
git commit -m "$(cat <<'EOF'
feat(mac): show the Fable weekly quota as a third gauge card

The popover showed 5h and Week while hiding the per-model Fable
quota — for the author's account that meant displaying 26% and 69%
while the number actually throttling them sat at 99%.

The card renders only when the API reports a Fable limit. Three
cards fit 316 pt of content width at 98.7 pt each, which leaves
78.7 pt inside the card padding; the verbose reset captions
("resets in 0h 56m") overflow that, so all 8 locales move to a
compact form ("0h56m"). The surrounding labelled gauge makes the
dropped "resets" wording unambiguous.

Whichever gauge Anthropic flags is_active gets a 1 pt border in its
tint. Danger colouring alone doesn't convey it: a scoped limit at
99% blocks one model rather than the whole account, so "red number"
and "this is what's stopping you" are different facts.

Fable's tint is purple — green and teal are taken by 5h and week,
and purple reads clearly in both popover themes.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Popover dismisses on outside click and after 10 idle seconds

**Files:**
- Modify: `Apps/ClaudeWatchMac/Popover/PopoverController.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks — this task is independent of the Fable work.
- Produces: no new public API. `PopoverController.toggle(from:)` keeps its signature.

- [ ] **Step 1: Add the dismissal machinery**

In `Apps/ClaudeWatchMac/Popover/PopoverController.swift`, add three stored properties and two constants to the class, immediately after `let ctx: AppContext`:

```swift
    /// Seconds the pointer must stay outside the popover (with the
    /// popover also not holding keyboard focus) before it closes.
    private static let autoHideAfter: TimeInterval = 10.0
    /// How often the idle check runs. Polling beats NSTrackingArea
    /// here: the popover rebuilds its SwiftUI content tree on every
    /// open, and tracking areas installed inside an NSHostingController
    /// don't survive that reliably. At 0.5 s the cost is nil.
    private static let idlePollInterval: TimeInterval = 0.5

    /// Fires while the popover is shown; closes it once the pointer has
    /// been away for `autoHideAfter`.
    private var idleTimer: Timer?
    private var idleElapsed: TimeInterval = 0
    /// Global monitors only see events delivered to OTHER applications,
    /// so clicks inside our own popover never reach this handler and no
    /// self-dismissal guard is needed.
    private var outsideClickMonitor: Any?
```

- [ ] **Step 2: Start and stop the machinery around show/close**

Replace the `toggle(from:)` method:

```swift
    func toggle(from anchor: NSStatusBarButton) {
        if popover.isShown {
            close()
        } else {
            // Rebuild the SwiftUI tree on every open. Without this, the
            // segmented picker shows nothing selected and the gauge bars
            // stay empty until the first interaction inside the popover —
            // a known issue with SwiftUI inside NSPopover where the view
            // doesn't re-evaluate @ObservedObject changes while offscreen.
            rebuildContent()
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
            startDismissalWatchers()
        }
    }

    /// Single close path so the timer and monitor can never outlive the
    /// popover, no matter which of the three dismissal triggers fired.
    func close() {
        stopDismissalWatchers()
        popover.performClose(nil)
    }

    /// `.transient` alone doesn't dismiss this popover: in an
    /// LSUIElement process, clicking the status item doesn't activate
    /// the app, so the outside-click event that `.transient` waits for
    /// never arrives. Calling NSApp.activate would fix that but steals
    /// keyboard focus from whatever the user was doing — too rude for
    /// glance-at-a-number UI. So we watch for outside clicks ourselves.
    private func startDismissalWatchers() {
        idleElapsed = 0
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
        let timer = Timer(timeInterval: Self.idlePollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickIdle() }
        }
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    private func stopDismissalWatchers() {
        idleTimer?.invalidate()
        idleTimer = nil
        idleElapsed = 0
        if let m = outsideClickMonitor {
            NSEvent.removeMonitor(m)
            outsideClickMonitor = nil
        }
    }

    /// The pointer being inside the popover, or the popover holding
    /// keyboard focus, both count as "the user is still using this".
    /// The focus clause matters because clicking a control inside the
    /// popover activates the app — without it, a user who clicked a
    /// timeframe button and then moved the mouse off would get the
    /// popover yanked mid-interaction.
    private func tickIdle() {
        guard popover.isShown, let window = popover.contentViewController?.view.window else {
            return
        }
        let pointerInside = window.frame.contains(NSEvent.mouseLocation)
        if pointerInside || window.isKeyWindow {
            idleElapsed = 0
            return
        }
        idleElapsed += Self.idlePollInterval
        if idleElapsed >= Self.autoHideAfter {
            close()
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

- [ ] **Step 4: Verify the four dismissal behaviors by hand**

There is no automated test for this — the behavior is entirely about real pointer position and window focus, which XCTest cannot drive meaningfully for an `NSPopover` in an `LSUIElement` app. Run the Debug build and check each case:

```bash
open "$(xcodebuild -project ClaudeWatch.xcodeproj -scheme ClaudeWatchMac -configuration Debug -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2}')/ClaudeWatchMac.app"
```

1. Open the popover, click on the desktop → closes immediately.
2. Open the popover, move the pointer away without clicking, wait → closes after ~10 s.
3. Open the popover, keep the pointer hovering over it for 30 s → stays open.
4. Open the popover, click a timeframe button, move the pointer away → closes after ~10 s (the click doesn't pin it open forever).
5. Open the popover, click the menu bar icon again → closes immediately.

- [ ] **Step 5: Commit**

```bash
git add Apps/ClaudeWatchMac/Popover/PopoverController.swift
git commit -m "$(cat <<'EOF'
fix(mac): popover now dismisses on outside click and after 10s idle

`.transient` never worked here. In an LSUIElement process, clicking
the status item doesn't activate the app, so the outside-click event
the behavior waits for never arrives and the popover stayed open
indefinitely.

NSApp.activate(ignoringOtherApps:) would have fixed it but steals
keyboard focus from whatever the user was doing — too disruptive for
a popover whose whole job is showing a number at a glance. Instead a
global NSEvent monitor watches for clicks landing in other apps.
Global monitors never see events delivered to our own process, so
clicks inside the popover can't self-dismiss it.

Adds the requested 10-second idle dismissal on a 0.5 s polling timer.
Polling rather than NSTrackingArea because the popover rebuilds its
SwiftUI content tree on every open and tracking areas inside an
NSHostingController don't survive that reliably.

Idle resets when the pointer is inside the popover OR the popover
holds keyboard focus. The focus clause matters: clicking a control
inside the popover activates the app, and without it a user who
clicked a timeframe button and then moved the mouse away would get
the popover yanked out from under a live interaction.

Timer and monitor are both created in startDismissalWatchers and torn
down in stopDismissalWatchers, reached through a single close() path,
so neither can outlive the popover regardless of which trigger fired.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review

**1. Spec coverage**

| Spec requirement | Task |
|---|---|
| Parse `limits[]`, match `weekly_scoped` + `display_name == "Fable"` | 1 (Step 4) |
| `usedFable` / `resetTimeFable` / `fableIsActive` on `UsageSnapshot` | 1 (Step 1) |
| `fractionFable` computed property | 1 (Step 1) |
| `limits` optional so old shapes don't throw `schemaDrift` | 1 (Step 4, test in Step 2) |
| Percent × 100 scale against ceiling 10 000 | 1 (Step 4) |
| Migration `v2`, three nullable columns | 2 (Step 3) |
| `snapshots_5min` deliberately unchanged | 2 (Step 3 comment) |
| `SnapshotRepository` insert/read | 2 (Step 4) |
| Third gauge card, conditional on non-nil | 3 (Step 5) |
| Cards shrink to 98.7 pt automatically | 3 (Step 5 — `frame(maxWidth: .infinity)` already on `GaugeCardView`) |
| Compact reset captions, 8 locales | 3 (Step 3) |
| `popover.gauge.fable`, 8 locales | 3 (Step 4) |
| `ChartPalette.actualFable` purple | 3 (Step 1) |
| `is_active` border | 3 (Step 2, wired in Step 5) |
| No Fable line in chart | not implemented — correct, spec lists it out of scope |
| Outside-click monitor | 4 (Step 2) |
| 10 s idle timer, 0.5 s poll | 4 (Step 2) |
| `10.0` / `0.5` as named constants | 4 (Step 1) |
| Timer + monitor torn down on close | 4 (Step 2 — single `close()` path) |
| 4 scraper tests | 1 (Step 2) |
| Migration test | 2 (Step 1 — `test_insertWithoutFable_readsBackAsNil` plus the Step 7 on-disk check) |

One spec deviation, deliberate: the spec's migration test described running `v1`, inserting raw SQL, then migrating. GRDB's `DatabaseMigrator` has no public "migrate up to version X" on a partially-migrated in-memory queue that is worth the setup complexity here, so Task 2 covers the same risk two cheaper ways — a unit test asserting a Fable-less insert reads back `nil` (identical to what a legacy row produces), plus a Step 7 check that runs the actual `ALTER TABLE` statements against a copy of the developer's real `v1` database and asserts zero row loss.

**2. Placeholder scan** — no TBD/TODO/"handle edge cases"/"similar to Task N". Every code step carries complete code; every command step carries the exact command and its expected output.

**3. Type consistency**

| Name | Defined | Used |
|---|---|---|
| `usedFable: Int?` | Task 1 Step 1 | Task 1 Step 4, Task 2 Steps 1/4 |
| `resetTimeFable: Date?` | Task 1 Step 1 | Task 1 Step 4, Task 2 Steps 1/4, Task 3 Step 5 |
| `fableIsActive: Bool` | Task 1 Step 1 | Task 1 Step 4, Task 2 Steps 1/4, Task 3 Step 5 |
| `fractionFable: Double?` | Task 1 Step 1 | Task 3 Step 5 |
| `Response.Limit` | Task 1 Step 4 | Task 1 Step 4 only |
| `fableDisplayName` | Task 1 Step 4 | Task 1 Step 4 only |
| `used_fable` / `reset_fable` / `fable_is_active` | Task 2 Step 3 | Task 2 Steps 4, 7 |
| `ChartPalette.actualFable` | Task 3 Step 1 | Task 3 Step 5 |
| `GaugeCardView.isActive` | Task 3 Step 2 | Task 3 Step 5 |
| `popover.gauge.fable` | Task 3 Step 4 | Task 3 Step 5 |
| `autoHideAfter` / `idlePollInterval` | Task 4 Step 1 | Task 4 Step 2 |
| `close()` / `startDismissalWatchers()` / `stopDismissalWatchers()` / `tickIdle()` | Task 4 Step 2 | Task 4 Step 2 |

All names agree across tasks.
