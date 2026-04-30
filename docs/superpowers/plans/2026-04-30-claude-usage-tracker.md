# Claude Usage Tracker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS menu bar app + iOS companion app + iOS widgets that scrape `claude.ai/settings/usage` to display 5h-window and weekly usage with charts, forecast, and CloudKit-synced history. Spec: `docs/superpowers/specs/2026-04-30-claude-usage-tracker-design.md`.

**Architecture:** Native SwiftUI. One Swift Package (`UsageCore`) shared by three targets: macOS app (`LSUIElement`), iOS app, iOS Widget extension. Each device polls claude.ai independently every 90s, writes snapshots to a local SQLite cache (App Group container on iOS), and asynchronously syncs derived history to a CloudKit private database. Auth lives in local Keychain only — never iCloud-synced.

**Tech Stack:** Swift 5.10+, SwiftUI, GRDB.swift (SQLite), Swift Charts, WidgetKit, WKWebView, CloudKit, UserNotifications, XCTest, swift-testing.

---

## File structure

```
ClaudeUsage/                                 ← repo root
├── ClaudeUsage.xcworkspace
├── Packages/
│   └── UsageCore/                           ← shared Swift Package
│       ├── Package.swift
│       ├── Sources/UsageCore/
│       │   ├── Models/{UsageSnapshot,ForecastResult,AlertKind,ScrapeError,Plan}.swift
│       │   ├── Auth/{DeviceID,KeychainStore,CookieReader}.swift
│       │   ├── Storage/{Database,SnapshotRepository,SettingsRepository,AlertStateRepository,RetentionJob}.swift
│       │   ├── Scraping/{UsageScraper,JSONUsageScraper,HTMLUsageScraper,ScraperFactory,EndpointConfig}.swift
│       │   ├── Forecast/{LinearForecaster,BaselineForecaster}.swift
│       │   ├── Polling/{PollingTimer,UsageController}.swift
│       │   ├── Sync/{CloudKitSync,SyncRecordMapper}.swift
│       │   └── Notifications/{AlertEngine,NotificationDispatcher}.swift
│       └── Tests/UsageCoreTests/            ← mirror structure
├── Apps/
│   ├── ClaudeUsageMac/                      ← macOS app target
│   │   ├── ClaudeUsageMacApp.swift
│   │   ├── MenuBar/{StatusItemController}.swift
│   │   ├── Popover/{PopoverController,PopoverRootView,GaugeCardView,ChartView,ForecastCaptionView,TimeframePicker,FooterView}.swift
│   │   ├── Auth/{LoginWindowController,LoginWebView,HiddenChallengeView}.swift
│   │   └── Settings/{SettingsWindow,AccountPane,AlertsPane,DataPane}.swift
│   ├── ClaudeUsageiOS/                      ← iOS app target
│   │   ├── ClaudeUsageiOSApp.swift
│   │   ├── Main/{MainScreenView,RecentActivitySection,DevicesSection}.swift
│   │   ├── Auth/{LoginSheet}.swift
│   │   ├── Onboarding/{OnboardingOverlay}.swift
│   │   └── Settings/{SettingsSheet}.swift
│   └── ClaudeUsageWidgets/                  ← iOS Widget extension
│       ├── WidgetBundle.swift
│       ├── Provider/{TimelineProvider,SnapshotEntry}.swift
│       ├── Home/{SmallWidget,MediumWidget,LargeWidget}.swift
│       └── Lock/{LockCircularWidget,LockRectangularWidget}.swift
└── docs/
    ├── superpowers/specs/2026-04-30-claude-usage-tracker-design.md
    └── superpowers/plans/2026-04-30-claude-usage-tracker.md   ← this file
```

The package owns all logic; app targets are thin presentation shells. Widget extension imports `UsageCore` and reads SQLite directly.

---

# Phase 1 — Project skeleton & Swift Package

### Task 1: Initialize Xcode workspace and Swift package

**Files:**
- Create: `ClaudeUsage.xcworkspace/contents.xcworkspacedata`
- Create: `Packages/UsageCore/Package.swift`
- Create: `Packages/UsageCore/Sources/UsageCore/UsageCore.swift`
- Create: `Packages/UsageCore/Tests/UsageCoreTests/UsageCoreTests.swift`

- [ ] **Step 1: Create empty workspace via Xcode (or scripted)**

```bash
mkdir -p Packages/UsageCore/Sources/UsageCore Packages/UsageCore/Tests/UsageCoreTests
```

Create `ClaudeUsage.xcworkspace/contents.xcworkspacedata`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Workspace version="1.0">
  <FileRef location="group:Packages/UsageCore"></FileRef>
</Workspace>
```

- [ ] **Step 2: Write Package.swift**

```swift
// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "UsageCore",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "UsageCore", targets: ["UsageCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.27.0")
    ],
    targets: [
        .target(name: "UsageCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"])
    ]
)
```

- [ ] **Step 3: Add a sentinel placeholder file**

`Sources/UsageCore/UsageCore.swift`:

```swift
public enum UsageCore {
    public static let version = "0.1.0"
}
```

- [ ] **Step 4: Add a sentinel test**

`Tests/UsageCoreTests/UsageCoreTests.swift`:

```swift
import XCTest
@testable import UsageCore

final class UsageCoreSentinelTests: XCTestCase {
    func test_version_is_set() {
        XCTAssertEqual(UsageCore.version, "0.1.0")
    }
}
```

- [ ] **Step 5: Run `swift test` from `Packages/UsageCore/`**

Expected: 1 test, passing.

```bash
cd Packages/UsageCore && swift test
```

- [ ] **Step 6: Commit**

```bash
git add ClaudeUsage.xcworkspace Packages/
git commit -m "feat: scaffold UsageCore Swift package with sentinel test"
```

---

# Phase 2 — Models

### Task 2: `Plan` enum

**Files:**
- Create: `Sources/UsageCore/Models/Plan.swift`
- Create: `Tests/UsageCoreTests/Models/PlanTests.swift`

- [ ] **Step 1: Failing test**

```swift
import XCTest
@testable import UsageCore

final class PlanTests: XCTestCase {
    func test_known_plan_strings_decode_correctly() {
        XCTAssertEqual(Plan(rawString: "Pro"), .pro)
        XCTAssertEqual(Plan(rawString: "Max 5x"), .max5x)
        XCTAssertEqual(Plan(rawString: "Max 20x"), .max20x)
        XCTAssertEqual(Plan(rawString: "Team"), .team)
        XCTAssertEqual(Plan(rawString: "Free"), .free)
    }
    func test_unknown_string_becomes_custom() {
        XCTAssertEqual(Plan(rawString: "Enterprise"), .custom("Enterprise"))
    }
    func test_displayName() {
        XCTAssertEqual(Plan.pro.displayName, "Pro")
        XCTAssertEqual(Plan.custom("Enterprise").displayName, "Enterprise")
    }
}
```

- [ ] **Step 2: Run** `swift test --filter PlanTests` → fail (Plan doesn't exist).

- [ ] **Step 3: Implement**

```swift
import Foundation

public enum Plan: Equatable, Hashable, Codable {
    case pro
    case max5x
    case max20x
    case team
    case free
    case custom(String)

    public init(rawString: String) {
        switch rawString {
        case "Pro": self = .pro
        case "Max 5x": self = .max5x
        case "Max 20x": self = .max20x
        case "Team": self = .team
        case "Free": self = .free
        default: self = .custom(rawString)
        }
    }

    public var displayName: String {
        switch self {
        case .pro: return "Pro"
        case .max5x: return "Max 5x"
        case .max20x: return "Max 20x"
        case .team: return "Team"
        case .free: return "Free"
        case .custom(let s): return s
        }
    }
}
```

- [ ] **Step 4: Run** `swift test --filter PlanTests` → pass.
- [ ] **Step 5: Commit** `git commit -am "feat(models): Plan enum with raw-string parsing"`

### Task 3: `UsageSnapshot` model

**Files:**
- Create: `Sources/UsageCore/Models/UsageSnapshot.swift`
- Create: `Tests/UsageCoreTests/Models/UsageSnapshotTests.swift`

- [ ] **Step 1: Failing test**

```swift
import XCTest
@testable import UsageCore

final class UsageSnapshotTests: XCTestCase {
    func test_initialization_holds_all_fields() {
        let now = Date()
        let snap = UsageSnapshot(
            timestamp: now,
            plan: .pro,
            used5h: 12_000, ceiling5h: 100_000, resetTime5h: now.addingTimeInterval(3600 * 4),
            usedWeek: 50_000, ceilingWeek: 1_000_000, resetTimeWeek: now.addingTimeInterval(86400 * 5),
            sourceVersion: "json-v1",
            raw: Data("{}".utf8)
        )
        XCTAssertEqual(snap.used5h, 12_000)
        XCTAssertEqual(snap.fraction5h, 0.12, accuracy: 0.0001)
        XCTAssertEqual(snap.fractionWeek, 0.05, accuracy: 0.0001)
    }
    func test_fraction_clamps_at_one() {
        let now = Date()
        let snap = UsageSnapshot(
            timestamp: now, plan: .pro,
            used5h: 200_000, ceiling5h: 100_000, resetTime5h: now,
            usedWeek: 0, ceilingWeek: 1, resetTimeWeek: now,
            sourceVersion: "json-v1", raw: Data()
        )
        XCTAssertEqual(snap.fraction5h, 1.0)
    }
}
```

- [ ] **Step 2: Run** → fail.
- [ ] **Step 3: Implement**

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

    public init(timestamp: Date, plan: Plan,
                used5h: Int, ceiling5h: Int, resetTime5h: Date,
                usedWeek: Int, ceilingWeek: Int, resetTimeWeek: Date,
                sourceVersion: String, raw: Data) {
        self.timestamp = timestamp
        self.plan = plan
        self.used5h = used5h; self.ceiling5h = ceiling5h; self.resetTime5h = resetTime5h
        self.usedWeek = usedWeek; self.ceilingWeek = ceilingWeek; self.resetTimeWeek = resetTimeWeek
        self.sourceVersion = sourceVersion
        self.raw = raw
    }

    public var fraction5h: Double {
        guard ceiling5h > 0 else { return 0 }
        return min(1.0, Double(used5h) / Double(ceiling5h))
    }
    public var fractionWeek: Double {
        guard ceilingWeek > 0 else { return 0 }
        return min(1.0, Double(usedWeek) / Double(ceilingWeek))
    }
    public var currentWindowStart5h: Date {
        resetTime5h.addingTimeInterval(-5 * 3600)
    }
}
```

- [ ] **Step 4: Run** → pass.
- [ ] **Step 5: Commit** `git commit -am "feat(models): UsageSnapshot with derived fractions"`

### Task 4: `ScrapeError` and `AlertKind` enums

**Files:**
- Create: `Sources/UsageCore/Models/ScrapeError.swift`
- Create: `Sources/UsageCore/Models/AlertKind.swift`
- Create: `Tests/UsageCoreTests/Models/ScrapeErrorTests.swift`

- [ ] **Step 1: Failing test for ScrapeError**

```swift
import XCTest
@testable import UsageCore

final class ScrapeErrorTests: XCTestCase {
    func test_error_categories() {
        XCTAssertTrue(ScrapeError.authExpired.isAuthRelated)
        XCTAssertTrue(ScrapeError.cloudflareChallenge.requiresWebViewRefresh)
        XCTAssertFalse(ScrapeError.network(URLError(.timedOut)).isAuthRelated)
    }
}
```

- [ ] **Step 2: Run** → fail.
- [ ] **Step 3: Implement**

`ScrapeError.swift`:

```swift
import Foundation

public enum ScrapeError: Error, Equatable {
    case authExpired
    case cloudflareChallenge
    case schemaDrift(version: String, payload: Data)
    case network(URLError)
    case rateLimited(retryAfter: TimeInterval?)
    case unknown(String)

    public var isAuthRelated: Bool {
        if case .authExpired = self { return true }
        return false
    }
    public var requiresWebViewRefresh: Bool {
        if case .cloudflareChallenge = self { return true }
        return false
    }

    public static func == (lhs: ScrapeError, rhs: ScrapeError) -> Bool {
        switch (lhs, rhs) {
        case (.authExpired, .authExpired): return true
        case (.cloudflareChallenge, .cloudflareChallenge): return true
        case let (.schemaDrift(a, _), .schemaDrift(b, _)): return a == b
        case let (.network(a), .network(b)): return a.code == b.code
        case let (.rateLimited(a), .rateLimited(b)): return a == b
        case let (.unknown(a), .unknown(b)): return a == b
        default: return false
        }
    }
}
```

`AlertKind.swift`:

```swift
import Foundation

public enum AlertKind: String, CaseIterable, Codable {
    case fiveHourForecast = "5h-forecast"
    case fiveHourHit = "5h-hit"
    case weekNinety = "week-90"
    case weekHundred = "week-100"
    case authExpired = "auth-expired"
    case scrapeBroken = "scrape-broken"

    public var defaultEnabled: Bool {
        switch self {
        case .scrapeBroken: return true
        default: return true
        }
    }
}
```

- [ ] **Step 4: Run** → pass.
- [ ] **Step 5: Commit** `git commit -am "feat(models): ScrapeError and AlertKind"`

### Task 5: `ForecastResult` model

**Files:**
- Create: `Sources/UsageCore/Models/ForecastResult.swift`
- Create: `Tests/UsageCoreTests/Models/ForecastResultTests.swift`

- [ ] **Step 1: Failing test**

```swift
import XCTest
@testable import UsageCore

final class ForecastResultTests: XCTestCase {
    func test_lowConfidence_when_R2_below_threshold() {
        let r = ForecastResult(slope: 1, intercept: 0, projectedHitTime: nil, line: [], rSquared: 0.3)
        XCTAssertTrue(r.isLowConfidence)
    }
    func test_highConfidence_when_R2_above_threshold() {
        let r = ForecastResult(slope: 1, intercept: 0, projectedHitTime: nil, line: [], rSquared: 0.7)
        XCTAssertFalse(r.isLowConfidence)
    }
}
```

- [ ] **Step 2: Run** → fail.
- [ ] **Step 3: Implement**

```swift
import Foundation

public struct ForecastPoint: Equatable, Codable {
    public let time: Date
    public let projectedFraction: Double
    public init(time: Date, projectedFraction: Double) {
        self.time = time; self.projectedFraction = projectedFraction
    }
}

public struct ForecastResult: Equatable, Codable {
    public let slope: Double          // tokens/sec
    public let intercept: Double      // tokens at now
    public let projectedHitTime: Date?
    public let line: [ForecastPoint]
    public let rSquared: Double

    public static let lowConfidenceThreshold: Double = 0.5

    public var isLowConfidence: Bool { rSquared < Self.lowConfidenceThreshold }

    public init(slope: Double, intercept: Double, projectedHitTime: Date?, line: [ForecastPoint], rSquared: Double) {
        self.slope = slope; self.intercept = intercept
        self.projectedHitTime = projectedHitTime
        self.line = line; self.rSquared = rSquared
    }
}
```

- [ ] **Step 4: Run** → pass.
- [ ] **Step 5: Commit** `git commit -am "feat(models): ForecastResult"`

---

# Phase 3 — Storage (SQLite via GRDB)

### Task 6: `Database` setup and migration

**Files:**
- Create: `Sources/UsageCore/Storage/Database.swift`
- Create: `Tests/UsageCoreTests/Storage/DatabaseTests.swift`

- [ ] **Step 1: Failing test**

```swift
import XCTest
import GRDB
@testable import UsageCore

final class DatabaseTests: XCTestCase {
    func test_migration_creates_all_tables() throws {
        let dbq = try DatabaseQueue()
        try Database.migrator.migrate(dbq)
        try dbq.read { db in
            for t in ["snapshots", "snapshots_5min", "settings", "alert_state"] {
                XCTAssertTrue(try db.tableExists(t), "missing table \(t)")
            }
        }
    }
}
```

- [ ] **Step 2: Run** → fail.
- [ ] **Step 3: Implement**

```swift
import Foundation
import GRDB

public enum Database {
    public static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE snapshots (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    device_id TEXT NOT NULL,
                    ts INTEGER NOT NULL,
                    plan TEXT NOT NULL,
                    used_5h INTEGER NOT NULL,
                    ceiling_5h INTEGER NOT NULL,
                    reset_5h INTEGER NOT NULL,
                    used_week INTEGER NOT NULL,
                    ceiling_week INTEGER NOT NULL,
                    reset_week INTEGER NOT NULL,
                    source_version TEXT NOT NULL,
                    synced_to_cloud INTEGER NOT NULL DEFAULT 0
                );
                CREATE INDEX idx_snapshots_ts ON snapshots(ts);

                CREATE TABLE snapshots_5min (
                    bucket_start INTEGER NOT NULL,
                    device_id TEXT NOT NULL,
                    plan TEXT NOT NULL,
                    used_5h_avg INTEGER NOT NULL,
                    ceiling_5h INTEGER NOT NULL,
                    used_week_avg INTEGER NOT NULL,
                    ceiling_week INTEGER NOT NULL,
                    bucket_count INTEGER NOT NULL,
                    PRIMARY KEY (bucket_start, device_id)
                );
                CREATE INDEX idx_snapshots_5min_bucket ON snapshots_5min(bucket_start);

                CREATE TABLE settings (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                );

                CREATE TABLE alert_state (
                    kind TEXT PRIMARY KEY,
                    last_fired_at INTEGER,
                    snoozed_until INTEGER
                );
            """)
        }
        return m
    }

    public static func openOnDisk(at url: URL) throws -> DatabaseQueue {
        let q = try DatabaseQueue(path: url.path)
        try migrator.migrate(q)
        return q
    }
}
```

- [ ] **Step 4: Run** → pass.
- [ ] **Step 5: Commit** `git commit -am "feat(storage): GRDB migration for usage.db schema"`

### Task 7: `SnapshotRepository` — insert + fetch recent

**Files:**
- Create: `Sources/UsageCore/Storage/SnapshotRepository.swift`
- Create: `Tests/UsageCoreTests/Storage/SnapshotRepositoryTests.swift`

- [ ] **Step 1: Failing test**

```swift
import XCTest
import GRDB
@testable import UsageCore

final class SnapshotRepositoryTests: XCTestCase {
    var dbq: DatabaseQueue!
    var repo: SnapshotRepository!

    override func setUp() {
        dbq = try! DatabaseQueue()
        try! Database.migrator.migrate(dbq)
        repo = SnapshotRepository(dbq: dbq, deviceID: "test-device")
    }

    func test_insert_then_fetchRecent_returns_inserted_rows() throws {
        let now = Date()
        let snap = makeSnap(ts: now)
        try repo.insert(snap)
        let recent = try repo.fetchRecent(within: 60 * 60)
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent[0].used5h, snap.used5h)
    }

    func test_fetchRecent_excludes_old_rows() throws {
        try repo.insert(makeSnap(ts: Date().addingTimeInterval(-7200)))
        try repo.insert(makeSnap(ts: Date()))
        let recent = try repo.fetchRecent(within: 3600)
        XCTAssertEqual(recent.count, 1)
    }

    private func makeSnap(ts: Date) -> UsageSnapshot {
        UsageSnapshot(timestamp: ts, plan: .pro,
            used5h: 1000, ceiling5h: 100_000, resetTime5h: ts.addingTimeInterval(3600 * 4),
            usedWeek: 5000, ceilingWeek: 1_000_000, resetTimeWeek: ts.addingTimeInterval(86400 * 5),
            sourceVersion: "json-v1", raw: Data())
    }
}
```

- [ ] **Step 2: Run** → fail.
- [ ] **Step 3: Implement**

```swift
import Foundation
import GRDB

public struct SnapshotRepository {
    let dbq: DatabaseQueue
    let deviceID: String

    public init(dbq: DatabaseQueue, deviceID: String) {
        self.dbq = dbq; self.deviceID = deviceID
    }

    public func insert(_ s: UsageSnapshot) throws {
        try dbq.write { db in
            try db.execute(sql: """
                INSERT INTO snapshots
                (device_id, ts, plan, used_5h, ceiling_5h, reset_5h,
                 used_week, ceiling_week, reset_week, source_version, synced_to_cloud)
                VALUES (?,?,?,?,?,?,?,?,?,?,0)
            """, arguments: [
                deviceID, Int(s.timestamp.timeIntervalSince1970), s.plan.displayName,
                s.used5h, s.ceiling5h, Int(s.resetTime5h.timeIntervalSince1970),
                s.usedWeek, s.ceilingWeek, Int(s.resetTimeWeek.timeIntervalSince1970),
                s.sourceVersion
            ])
        }
    }

    public func fetchRecent(within seconds: TimeInterval, now: Date = Date()) throws -> [UsageSnapshot] {
        let cutoff = Int(now.timeIntervalSince1970 - seconds)
        return try dbq.read { db in
            let rows = try Row.fetchAll(db, sql:
                "SELECT * FROM snapshots WHERE ts >= ? ORDER BY ts ASC", arguments: [cutoff])
            return rows.map(Self.fromRow)
        }
    }

    public func mostRecent() throws -> UsageSnapshot? {
        try dbq.read { db in
            let row = try Row.fetchOne(db, sql:
                "SELECT * FROM snapshots ORDER BY ts DESC LIMIT 1")
            return row.map(Self.fromRow)
        }
    }

    private static func fromRow(_ r: Row) -> UsageSnapshot {
        UsageSnapshot(
            timestamp: Date(timeIntervalSince1970: r["ts"]),
            plan: Plan(rawString: r["plan"]),
            used5h: r["used_5h"], ceiling5h: r["ceiling_5h"],
            resetTime5h: Date(timeIntervalSince1970: r["reset_5h"]),
            usedWeek: r["used_week"], ceilingWeek: r["ceiling_week"],
            resetTimeWeek: Date(timeIntervalSince1970: r["reset_week"]),
            sourceVersion: r["source_version"],
            raw: Data()
        )
    }
}
```

- [ ] **Step 4: Run** → pass.
- [ ] **Step 5: Commit** `git commit -am "feat(storage): SnapshotRepository insert + fetchRecent"`

### Task 8: `SettingsRepository`

**Files:**
- Create: `Sources/UsageCore/Storage/SettingsRepository.swift`
- Create: `Tests/UsageCoreTests/Storage/SettingsRepositoryTests.swift`

- [ ] **Step 1: Failing test**

```swift
import XCTest
import GRDB
@testable import UsageCore

final class SettingsRepositoryTests: XCTestCase {
    func test_set_then_get_returns_value() throws {
        let dbq = try DatabaseQueue()
        try Database.migrator.migrate(dbq)
        let repo = SettingsRepository(dbq: dbq)
        try repo.set(.selectedTimeframe, "8h")
        XCTAssertEqual(try repo.get(.selectedTimeframe), "8h")
    }
    func test_get_missing_key_returns_nil() throws {
        let dbq = try DatabaseQueue()
        try Database.migrator.migrate(dbq)
        let repo = SettingsRepository(dbq: dbq)
        XCTAssertNil(try repo.get(.theme))
    }
}
```

- [ ] **Step 2: Run** → fail.
- [ ] **Step 3: Implement**

```swift
import Foundation
import GRDB

public struct SettingsRepository {
    let dbq: DatabaseQueue
    public init(dbq: DatabaseQueue) { self.dbq = dbq }

    public enum Key: String {
        case selectedTimeframe        // "1h"|"8h"|"24h"|"1w"
        case theme                    // "auto"|"light"|"dark"
        case planOverride             // "Pro"|"Max 5x"|...
        case alertThresholds          // JSON
        case quietHoursStartMin       // "1320" (22:00)
        case quietHoursEndMin         // "480"  (08:00)
        case lastCloudSyncTs          // unix seconds
    }

    public func get(_ key: Key) throws -> String? {
        try dbq.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = ?", arguments: [key.rawValue])
        }
    }
    public func set(_ key: Key, _ value: String) throws {
        try dbq.write { db in
            try db.execute(sql:
                "INSERT INTO settings (key,value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                arguments: [key.rawValue, value])
        }
    }
}
```

- [ ] **Step 4: Run** → pass.
- [ ] **Step 5: Commit** `git commit -am "feat(storage): SettingsRepository"`

### Task 9: `AlertStateRepository`

**Files:**
- Create: `Sources/UsageCore/Storage/AlertStateRepository.swift`
- Create: `Tests/UsageCoreTests/Storage/AlertStateRepositoryTests.swift`

- [ ] **Step 1: Failing test**

```swift
import XCTest
import GRDB
@testable import UsageCore

final class AlertStateRepositoryTests: XCTestCase {
    func test_recordFire_updates_lastFiredAt() throws {
        let dbq = try DatabaseQueue(); try Database.migrator.migrate(dbq)
        let repo = AlertStateRepository(dbq: dbq)
        let t = Date()
        try repo.recordFire(.fiveHourForecast, at: t)
        XCTAssertEqual(try repo.lastFired(.fiveHourForecast)?.timeIntervalSince1970,
                       t.timeIntervalSince1970, accuracy: 1)
    }
    func test_snooze_persists() throws {
        let dbq = try DatabaseQueue(); try Database.migrator.migrate(dbq)
        let repo = AlertStateRepository(dbq: dbq)
        let until = Date().addingTimeInterval(3600)
        try repo.snooze(.fiveHourForecast, until: until)
        XCTAssertEqual(try repo.snoozedUntil(.fiveHourForecast)?.timeIntervalSince1970,
                       until.timeIntervalSince1970, accuracy: 1)
    }
}
```

- [ ] **Step 2: Run** → fail.
- [ ] **Step 3: Implement**

```swift
import Foundation
import GRDB

public struct AlertStateRepository {
    let dbq: DatabaseQueue
    public init(dbq: DatabaseQueue) { self.dbq = dbq }

    public func recordFire(_ kind: AlertKind, at: Date) throws {
        try dbq.write { db in
            try db.execute(sql: """
                INSERT INTO alert_state (kind, last_fired_at) VALUES (?, ?)
                ON CONFLICT(kind) DO UPDATE SET last_fired_at = excluded.last_fired_at
            """, arguments: [kind.rawValue, Int(at.timeIntervalSince1970)])
        }
    }
    public func lastFired(_ kind: AlertKind) throws -> Date? {
        try dbq.read { db in
            let v: Int? = try Int.fetchOne(db,
                sql: "SELECT last_fired_at FROM alert_state WHERE kind = ?",
                arguments: [kind.rawValue])
            return v.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        }
    }
    public func snooze(_ kind: AlertKind, until: Date) throws {
        try dbq.write { db in
            try db.execute(sql: """
                INSERT INTO alert_state (kind, snoozed_until) VALUES (?, ?)
                ON CONFLICT(kind) DO UPDATE SET snoozed_until = excluded.snoozed_until
            """, arguments: [kind.rawValue, Int(until.timeIntervalSince1970)])
        }
    }
    public func snoozedUntil(_ kind: AlertKind) throws -> Date? {
        try dbq.read { db in
            let v: Int? = try Int.fetchOne(db,
                sql: "SELECT snoozed_until FROM alert_state WHERE kind = ?",
                arguments: [kind.rawValue])
            return v.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        }
    }
}
```

- [ ] **Step 4: Run** → pass.
- [ ] **Step 5: Commit** `git commit -am "feat(storage): AlertStateRepository"`

### Task 10: `RetentionJob` — downsample + delete

**Files:**
- Create: `Sources/UsageCore/Storage/RetentionJob.swift`
- Create: `Tests/UsageCoreTests/Storage/RetentionJobTests.swift`

- [ ] **Step 1: Failing test**

```swift
import XCTest
import GRDB
@testable import UsageCore

final class RetentionJobTests: XCTestCase {
    func test_rows_older_than_7_days_collapse_into_5min_buckets() throws {
        let dbq = try DatabaseQueue(); try Database.migrator.migrate(dbq)
        let repo = SnapshotRepository(dbq: dbq, deviceID: "d1")
        let oldTs = Date().addingTimeInterval(-86400 * 8)
        for i in 0..<5 {
            try repo.insert(makeSnap(ts: oldTs.addingTimeInterval(Double(i) * 60), used5h: 1000 + i*10))
        }
        let job = RetentionJob(dbq: dbq)
        try job.run(now: Date())
        let buckets = try dbq.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM snapshots_5min")
        }
        XCTAssertEqual(buckets.count, 1)
        XCTAssertEqual(buckets[0]["bucket_count"] as Int, 5)
        let raw = try dbq.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM snapshots WHERE ts < ?",
                             arguments: [Int(Date().addingTimeInterval(-86400*7).timeIntervalSince1970)])!
        }
        XCTAssertEqual(raw, 0, "old raw rows should be deleted")
    }

    func test_rows_in_last_7_days_are_untouched() throws {
        let dbq = try DatabaseQueue(); try Database.migrator.migrate(dbq)
        let repo = SnapshotRepository(dbq: dbq, deviceID: "d1")
        try repo.insert(makeSnap(ts: Date(), used5h: 5000))
        let job = RetentionJob(dbq: dbq)
        try job.run(now: Date())
        XCTAssertEqual(try repo.fetchRecent(within: 60).count, 1)
    }

    private func makeSnap(ts: Date, used5h: Int) -> UsageSnapshot {
        UsageSnapshot(timestamp: ts, plan: .pro,
            used5h: used5h, ceiling5h: 100_000, resetTime5h: ts,
            usedWeek: 0, ceilingWeek: 1_000_000, resetTimeWeek: ts,
            sourceVersion: "json-v1", raw: Data())
    }
}
```

- [ ] **Step 2: Run** → fail.
- [ ] **Step 3: Implement**

```swift
import Foundation
import GRDB

public struct RetentionJob {
    public let dbq: DatabaseQueue
    public let rawRetentionDays: Int = 7
    public let downsampledRetentionDays: Int = 30
    public let bucketSeconds: Int = 300

    public init(dbq: DatabaseQueue) { self.dbq = dbq }

    public func run(now: Date = Date()) throws {
        let rawCutoff = Int(now.addingTimeInterval(-Double(rawRetentionDays * 86400)).timeIntervalSince1970)
        let downCutoff = Int(now.addingTimeInterval(-Double(downsampledRetentionDays * 86400)).timeIntervalSince1970)
        let bucket = bucketSeconds

        try dbq.write { db in
            try db.execute(sql: """
                INSERT INTO snapshots_5min (
                    bucket_start, device_id, plan,
                    used_5h_avg, ceiling_5h, used_week_avg, ceiling_week, bucket_count
                )
                SELECT
                    (ts / \(bucket)) * \(bucket) AS bucket_start,
                    device_id,
                    MAX(plan),
                    CAST(AVG(used_5h) AS INTEGER),
                    MAX(ceiling_5h),
                    CAST(AVG(used_week) AS INTEGER),
                    MAX(ceiling_week),
                    COUNT(*)
                FROM snapshots
                WHERE ts < ?
                GROUP BY bucket_start, device_id
                ON CONFLICT(bucket_start, device_id) DO NOTHING
            """, arguments: [rawCutoff])
            try db.execute(sql: "DELETE FROM snapshots WHERE ts < ?", arguments: [rawCutoff])
            try db.execute(sql: "DELETE FROM snapshots_5min WHERE bucket_start < ?", arguments: [downCutoff])
        }
    }
}
```

- [ ] **Step 4: Run** → pass.
- [ ] **Step 5: Commit** `git commit -am "feat(storage): RetentionJob downsamples + prunes"`

---

# Phase 4 — Auth: DeviceID, Keychain, Cookies

### Task 11: `DeviceID` — stable per-device UUID

**Files:**
- Create: `Sources/UsageCore/Auth/DeviceID.swift`
- Create: `Tests/UsageCoreTests/Auth/DeviceIDTests.swift`

- [ ] **Step 1: Failing test**

```swift
import XCTest
@testable import UsageCore

final class DeviceIDTests: XCTestCase {
    func test_first_call_generates_id_subsequent_returns_same() throws {
        let store = InMemoryKeychain()
        let id1 = try DeviceID.getOrCreate(in: store)
        let id2 = try DeviceID.getOrCreate(in: store)
        XCTAssertEqual(id1, id2)
        XCTAssertFalse(id1.isEmpty)
    }
}
final class InMemoryKeychain: KeychainStoring {
    var dict: [String: Data] = [:]
    func read(service: String, account: String) throws -> Data? { dict["\(service)/\(account)"] }
    func write(service: String, account: String, data: Data) throws { dict["\(service)/\(account)"] = data }
    func delete(service: String, account: String) throws { dict["\(service)/\(account)"] = nil }
}
```

- [ ] **Step 2: Run** → fail.
- [ ] **Step 3: Implement** (also defines KeychainStoring protocol used by Task 12)

```swift
import Foundation

public protocol KeychainStoring {
    func read(service: String, account: String) throws -> Data?
    func write(service: String, account: String, data: Data) throws
    func delete(service: String, account: String) throws
}

public enum DeviceID {
    public static let service = "com.claudeusage.deviceid"
    public static let account = "device-uuid"

    public static func getOrCreate(in store: KeychainStoring) throws -> String {
        if let d = try store.read(service: service, account: account),
           let s = String(data: d, encoding: .utf8) {
            return s
        }
        let new = UUID().uuidString
        try store.write(service: service, account: account, data: Data(new.utf8))
        return new
    }
}
```

- [ ] **Step 4: Run** → pass.
- [ ] **Step 5: Commit** `git commit -am "feat(auth): DeviceID with KeychainStoring protocol"`

### Task 12: `KeychainStore` — real Keychain implementation

**Files:**
- Create: `Sources/UsageCore/Auth/KeychainStore.swift`

- [ ] **Step 1: No automated test (interacts with real Keychain). Implement directly:**

```swift
import Foundation
import Security

public struct KeychainStore: KeychainStoring {
    public init() {}

    public func read(service: String, account: String) throws -> Data? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let s = SecItemCopyMatching(q as CFDictionary, &item)
        switch s {
        case errSecSuccess: return item as? Data
        case errSecItemNotFound: return nil
        default: throw KeychainError.osStatus(s)
        }
    }

    public func write(service: String, account: String, data: Data) throws {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attrs: [String: Any] = [kSecValueData as String: data]
        let s = SecItemUpdate(q as CFDictionary, attrs as CFDictionary)
        if s == errSecItemNotFound {
            var add = q; add[kSecValueData as String] = data
            let a = SecItemAdd(add as CFDictionary, nil)
            if a != errSecSuccess { throw KeychainError.osStatus(a) }
        } else if s != errSecSuccess {
            throw KeychainError.osStatus(s)
        }
    }

    public func delete(service: String, account: String) throws {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let s = SecItemDelete(q as CFDictionary)
        if s != errSecSuccess && s != errSecItemNotFound {
            throw KeychainError.osStatus(s)
        }
    }
}

public enum KeychainError: Error { case osStatus(OSStatus) }
```

- [ ] **Step 2: Build** `cd Packages/UsageCore && swift build` → no errors.
- [ ] **Step 3: Commit** `git commit -am "feat(auth): real Keychain-backed KeychainStore"`

### Task 13: `CookieReader` — extract cookies from a `WKHTTPCookieStore`

**Files:**
- Create: `Sources/UsageCore/Auth/CookieReader.swift`
- Create: `Tests/UsageCoreTests/Auth/CookieReaderTests.swift`

- [ ] **Step 1: Failing test (uses `HTTPCookie` to simulate a fetched store)**

```swift
import XCTest
@testable import UsageCore

final class CookieReaderTests: XCTestCase {
    func test_packageCookies_serializes_known_names() {
        let session = HTTPCookie(properties: [
            .name: "sessionKey", .value: "abc", .domain: ".claude.ai", .path: "/"])!
        let cf = HTTPCookie(properties: [
            .name: "cf_clearance", .value: "xyz", .domain: ".claude.ai", .path: "/"])!
        let stranger = HTTPCookie(properties: [
            .name: "_ga", .value: "ignored", .domain: ".claude.ai", .path: "/"])!
        let pkg = CookieReader.package(from: [session, cf, stranger], userAgent: "TestUA/1.0")
        XCTAssertEqual(pkg.sessionKey, "abc")
        XCTAssertEqual(pkg.cfClearance, "xyz")
        XCTAssertEqual(pkg.userAgent, "TestUA/1.0")
        // _ga is dropped from the typed package but present in `all`
        XCTAssertEqual(pkg.all.count, 3)
    }
}
```

- [ ] **Step 2: Run** → fail.
- [ ] **Step 3: Implement**

```swift
import Foundation

public struct CookiePackage: Codable, Equatable {
    public var sessionKey: String?
    public var cfClearance: String?
    public var cfBm: String?
    public var userAgent: String
    public var all: [SerializedCookie]

    public struct SerializedCookie: Codable, Equatable {
        public let name: String
        public let value: String
        public let domain: String
        public let path: String
        public let isSecure: Bool
        public let isHTTPOnly: Bool
        public let expiresAt: Date?
    }
}

public enum CookieReader {
    public static func package(from cookies: [HTTPCookie], userAgent: String) -> CookiePackage {
        var pkg = CookiePackage(sessionKey: nil, cfClearance: nil, cfBm: nil, userAgent: userAgent, all: [])
        for c in cookies {
            switch c.name {
            case "sessionKey": pkg.sessionKey = c.value
            case "cf_clearance": pkg.cfClearance = c.value
            case "__cf_bm": pkg.cfBm = c.value
            default: break
            }
            pkg.all.append(.init(
                name: c.name, value: c.value, domain: c.domain, path: c.path,
                isSecure: c.isSecure, isHTTPOnly: c.isHTTPOnly, expiresAt: c.expiresDate))
        }
        return pkg
    }
}
```

- [ ] **Step 4: Run** → pass.
- [ ] **Step 5: Commit** `git commit -am "feat(auth): CookieReader serializes claude.ai cookies"`

### Task 14: Persist `CookiePackage` to Keychain

**Files:**
- Modify: `Sources/UsageCore/Auth/CookieReader.swift`
- Create: `Tests/UsageCoreTests/Auth/CookiePackageStoreTests.swift`

- [ ] **Step 1: Failing test**

```swift
import XCTest
@testable import UsageCore

final class CookiePackageStoreTests: XCTestCase {
    func test_save_then_load_roundtrips() throws {
        let kc = InMemoryKeychain()
        var pkg = CookiePackage(sessionKey: "s", cfClearance: "c", cfBm: nil,
                                userAgent: "UA", all: [])
        try CookiePackageStore(keychain: kc, deviceID: "d1").save(pkg)
        let loaded = try CookiePackageStore(keychain: kc, deviceID: "d1").load()
        XCTAssertEqual(loaded?.sessionKey, "s")
    }
}
```

- [ ] **Step 2: Run** → fail.
- [ ] **Step 3: Implement** (append to `CookieReader.swift` or new file `CookiePackageStore.swift`)

```swift
public struct CookiePackageStore {
    public static let service = "com.claudeusage.cookie"
    let keychain: KeychainStoring
    let deviceID: String
    public init(keychain: KeychainStoring, deviceID: String) {
        self.keychain = keychain; self.deviceID = deviceID
    }

    public func save(_ pkg: CookiePackage) throws {
        let data = try JSONEncoder().encode(pkg)
        try keychain.write(service: Self.service, account: deviceID, data: data)
    }
    public func load() throws -> CookiePackage? {
        guard let d = try keychain.read(service: Self.service, account: deviceID) else { return nil }
        return try JSONDecoder().decode(CookiePackage.self, from: d)
    }
    public func clear() throws {
        try keychain.delete(service: Self.service, account: deviceID)
    }
}
```

- [ ] **Step 4: Run** → pass.
- [ ] **Step 5: Commit** `git commit -am "feat(auth): CookiePackageStore persists cookies to Keychain"`

---

# Phase 5 — Scraper

### Task 15: `UsageScraper` protocol and `EndpointConfig`

**Files:**
- Create: `Sources/UsageCore/Scraping/UsageScraper.swift`
- Create: `Sources/UsageCore/Scraping/EndpointConfig.swift`

- [ ] **Step 1: No test for protocol declaration alone. Write directly.**

`UsageScraper.swift`:

```swift
import Foundation

public protocol UsageScraper {
    var sourceVersion: String { get }
    func fetchSnapshot() async throws -> UsageSnapshot
}
```

`EndpointConfig.swift`:

```swift
import Foundation

public struct EndpointConfig: Codable, Equatable {
    /// URL of the JSON endpoint discovered during implementation. TBD on first run.
    public var jsonEndpoint: URL?
    /// Path of the rendered settings page (always known).
    public var htmlEndpoint: URL = URL(string: "https://claude.ai/settings/usage")!

    public static let storedKey = "endpointConfig"

    public init(jsonEndpoint: URL? = nil) { self.jsonEndpoint = jsonEndpoint }
}
```

- [ ] **Step 2: Commit** `git commit -am "feat(scraping): UsageScraper protocol + EndpointConfig"`

### Task 16: `JSONUsageScraper` (parameterized; endpoint discovery later)

**Files:**
- Create: `Sources/UsageCore/Scraping/JSONUsageScraper.swift`
- Create: `Tests/UsageCoreTests/Scraping/JSONUsageScraperTests.swift`

> **Discovery note for implementer:** the actual endpoint URL and JSON shape are TBD. **Before implementing, open `https://claude.ai/settings/usage` in a real browser with DevTools → Network tab and identify the XHR/fetch call that returns the usage data.** Record the URL, query params, and response shape. The placeholder JSON below assumes a likely shape (`{ plan, fiveHourWindow:{used,limit,resetAt}, weeklyWindow:{used,limit,resetAt} }`) — adjust the `Codable` types in this task to match the actual response.

- [ ] **Step 1: Failing test (uses `URLProtocol` mock to inject a JSON response)**

```swift
import XCTest
@testable import UsageCore

final class JSONUsageScraperTests: XCTestCase {
    func test_fetchSnapshot_parses_known_shape() async throws {
        let body = """
        {"plan":"Pro",
         "fiveHourWindow":{"used":12345,"limit":100000,"resetAt":"2026-04-30T15:00:00Z"},
         "weeklyWindow":{"used":50000,"limit":1000000,"resetAt":"2026-05-04T00:00:00Z"}}
        """.data(using: .utf8)!
        URLProtocolMock.responses[URL(string: "https://claude.ai/api/usage")!] = (200, body)
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [URLProtocolMock.self]
        let session = URLSession(configuration: cfg)

        let scraper = JSONUsageScraper(
            endpoint: URL(string: "https://claude.ai/api/usage")!,
            cookies: CookiePackage(sessionKey: "s", cfClearance: nil, cfBm: nil, userAgent: "UA", all: []),
            session: session
        )
        let snap = try await scraper.fetchSnapshot()
        XCTAssertEqual(snap.plan, .pro)
        XCTAssertEqual(snap.used5h, 12345)
        XCTAssertEqual(snap.ceilingWeek, 1_000_000)
    }

    func test_401_throws_authExpired() async throws {
        URLProtocolMock.responses[URL(string: "https://claude.ai/api/usage")!] = (401, Data())
        let cfg = URLSessionConfiguration.ephemeral; cfg.protocolClasses = [URLProtocolMock.self]
        let session = URLSession(configuration: cfg)
        let scraper = JSONUsageScraper(
            endpoint: URL(string: "https://claude.ai/api/usage")!,
            cookies: CookiePackage(sessionKey: "", cfClearance: nil, cfBm: nil, userAgent: "UA", all: []),
            session: session)
        do { _ = try await scraper.fetchSnapshot(); XCTFail() }
        catch let e as ScrapeError { XCTAssertEqual(e, .authExpired) }
    }
}

final class URLProtocolMock: URLProtocol {
    static var responses: [URL: (Int, Data)] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for r: URLRequest) -> URLRequest { r }
    override func startLoading() {
        guard let url = request.url, let (status, body) = Self.responses[url] else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        let resp = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
```

- [ ] **Step 2: Run** → fail.
- [ ] **Step 3: Implement**

```swift
import Foundation

public struct JSONUsageScraper: UsageScraper {
    public let sourceVersion = "json-v1"
    public let endpoint: URL
    public let cookies: CookiePackage
    public let session: URLSession

    public init(endpoint: URL, cookies: CookiePackage, session: URLSession = .shared) {
        self.endpoint = endpoint; self.cookies = cookies; self.session = session
    }

    private struct Response: Decodable {
        let plan: String
        let fiveHourWindow: Window
        let weeklyWindow: Window
        struct Window: Decodable {
            let used: Int
            let limit: Int
            let resetAt: Date
        }
    }

    public func fetchSnapshot() async throws -> UsageSnapshot {
        var req = URLRequest(url: endpoint)
        req.timeoutInterval = 15
        req.setValue(cookies.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue(buildCookieHeader(), forHTTPHeaderField: "Cookie")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await session.data(for: req) }
        catch let e as URLError { throw ScrapeError.network(e) }

        guard let http = resp as? HTTPURLResponse else { throw ScrapeError.unknown("no HTTP response") }
        switch http.statusCode {
        case 200: break
        case 401, 403:
            if let txt = String(data: data, encoding: .utf8), txt.contains("Just a moment") || txt.contains("cf-challenge") {
                throw ScrapeError.cloudflareChallenge
            }
            throw ScrapeError.authExpired
        case 429:
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw ScrapeError.rateLimited(retryAfter: retry)
        default:
            throw ScrapeError.unknown("HTTP \(http.statusCode)")
        }

        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        do {
            let r = try dec.decode(Response.self, from: data)
            return UsageSnapshot(
                timestamp: Date(),
                plan: Plan(rawString: r.plan),
                used5h: r.fiveHourWindow.used,
                ceiling5h: r.fiveHourWindow.limit,
                resetTime5h: r.fiveHourWindow.resetAt,
                usedWeek: r.weeklyWindow.used,
                ceilingWeek: r.weeklyWindow.limit,
                resetTimeWeek: r.weeklyWindow.resetAt,
                sourceVersion: sourceVersion,
                raw: data)
        } catch {
            throw ScrapeError.schemaDrift(version: sourceVersion, payload: data)
        }
    }

    private func buildCookieHeader() -> String {
        var parts: [String] = []
        if let s = cookies.sessionKey { parts.append("sessionKey=\(s)") }
        if let c = cookies.cfClearance { parts.append("cf_clearance=\(c)") }
        if let b = cookies.cfBm { parts.append("__cf_bm=\(b)") }
        return parts.joined(separator: "; ")
    }
}
```

- [ ] **Step 4: Run** → pass.
- [ ] **Step 5: Commit** `git commit -am "feat(scraping): JSONUsageScraper with auth/rate-limit/cf handling"`

### Task 17: `HTMLUsageScraper` stub (deferred until JSON path is proven)

**Files:**
- Create: `Sources/UsageCore/Scraping/HTMLUsageScraper.swift`

- [ ] **Step 1: Implement** a stub that throws `.schemaDrift` if invoked. Real DOM-extraction logic ships with M2-equivalent tasks once we know how the page is structured.

```swift
import Foundation

public struct HTMLUsageScraper: UsageScraper {
    public let sourceVersion = "html-v1"
    public init() {}
    public func fetchSnapshot() async throws -> UsageSnapshot {
        throw ScrapeError.unknown("HTMLUsageScraper not implemented yet — discover endpoint first")
    }
}
```

- [ ] **Step 2: Commit** `git commit -am "feat(scraping): HTMLUsageScraper stub"`

### Task 18: `ScraperFactory` — chooses live scraper, records last success

**Files:**
- Create: `Sources/UsageCore/Scraping/ScraperFactory.swift`
- Create: `Tests/UsageCoreTests/Scraping/ScraperFactoryTests.swift`

- [ ] **Step 1: Failing test**

```swift
import XCTest
@testable import UsageCore

final class ScraperFactoryTests: XCTestCase {
    func test_returns_json_when_endpoint_is_set() {
        let cfg = EndpointConfig(jsonEndpoint: URL(string: "https://x")!)
        let pkg = CookiePackage(sessionKey: nil, cfClearance: nil, cfBm: nil, userAgent: "UA", all: [])
        let f = ScraperFactory(config: cfg, cookies: pkg)
        XCTAssertEqual(f.current().sourceVersion, "json-v1")
    }
    func test_falls_back_to_html_when_no_json_endpoint() {
        let cfg = EndpointConfig(jsonEndpoint: nil)
        let pkg = CookiePackage(sessionKey: nil, cfClearance: nil, cfBm: nil, userAgent: "UA", all: [])
        let f = ScraperFactory(config: cfg, cookies: pkg)
        XCTAssertEqual(f.current().sourceVersion, "html-v1")
    }
}
```

- [ ] **Step 2: Run** → fail.
- [ ] **Step 3: Implement**

```swift
import Foundation

public struct ScraperFactory {
    public let config: EndpointConfig
    public let cookies: CookiePackage
    public let session: URLSession

    public init(config: EndpointConfig, cookies: CookiePackage, session: URLSession = .shared) {
        self.config = config; self.cookies = cookies; self.session = session
    }

    public func current() -> UsageScraper {
        if let url = config.jsonEndpoint {
            return JSONUsageScraper(endpoint: url, cookies: cookies, session: session)
        }
        return HTMLUsageScraper()
    }
}
```

- [ ] **Step 4: Run** → pass.
- [ ] **Step 5: Commit** `git commit -am "feat(scraping): ScraperFactory selects JSON or HTML"`

---

# Phase 6 — Forecast math

### Task 19: `LinearForecaster` — weighted regression

**Files:**
- Create: `Sources/UsageCore/Forecast/LinearForecaster.swift`
- Create: `Tests/UsageCoreTests/Forecast/LinearForecasterTests.swift`

- [ ] **Step 1: Failing test**

```swift
import XCTest
@testable import UsageCore

final class LinearForecasterTests: XCTestCase {
    func test_perfect_line_predicts_hit_at_correct_time() {
        let now = Date()
        var snaps: [UsageSnapshot] = []
        for i in 0..<10 {
            let t = now.addingTimeInterval(-Double(60 - i*6))
            let used = i * 1000
            snaps.append(UsageSnapshot(
                timestamp: t, plan: .pro,
                used5h: used, ceiling5h: 100_000,
                resetTime5h: now.addingTimeInterval(3600 * 4),
                usedWeek: 0, ceilingWeek: 1_000_000,
                resetTimeWeek: now,
                sourceVersion: "json-v1", raw: Data()))
        }
        let result = LinearForecaster().forecast(snapshots: snaps, now: now)!
        XCTAssertGreaterThan(result.slope, 0)
        XCTAssertGreaterThan(result.rSquared, 0.95)
        XCTAssertNotNil(result.projectedHitTime)
    }

    func test_returns_nil_with_fewer_than_3_points() {
        let r = LinearForecaster().forecast(snapshots: [], now: Date())
        XCTAssertNil(r)
    }

    func test_negative_slope_yields_nil_projectedHitTime() {
        let now = Date()
        let snaps = (0..<5).map { i -> UsageSnapshot in
            UsageSnapshot(timestamp: now.addingTimeInterval(-Double(60 - i*15)),
                          plan: .pro,
                          used5h: max(1000, 5000 - i*800), ceiling5h: 100_000,
                          resetTime5h: now.addingTimeInterval(3600),
                          usedWeek: 0, ceilingWeek: 1_000_000, resetTimeWeek: now,
                          sourceVersion: "json-v1", raw: Data())
        }
        let r = LinearForecaster().forecast(snapshots: snaps, now: now)!
        XCTAssertNil(r.projectedHitTime)
    }
}
```

- [ ] **Step 2: Run** → fail.
- [ ] **Step 3: Implement**

```swift
import Foundation

public struct LinearForecaster {
    public let halfLifeSeconds: Double = 1800
    public init() {}

    /// Returns nil if fewer than 3 input points.
    public func forecast(snapshots: [UsageSnapshot], now: Date = Date()) -> ForecastResult? {
        guard snapshots.count >= 3 else { return nil }
        guard let last = snapshots.last else { return nil }
        let ceiling = Double(last.ceiling5h)

        let xs = snapshots.map { $0.timestamp.timeIntervalSince(now) }   // negative for past
        let ys = snapshots.map { Double($0.used5h) }
        let ws = xs.map { exp($0 / halfLifeSeconds) }                    // bigger for x≈0

        let sumW = ws.reduce(0, +)
        let mx = zip(xs, ws).map(*).reduce(0,+) / sumW
        let my = zip(ys, ws).map(*).reduce(0,+) / sumW
        let num = zip(zip(xs, ys), ws).map { (xy, w) in w * (xy.0 - mx) * (xy.1 - my) }.reduce(0,+)
        let den = zip(xs, ws).map { (x, w) in w * (x - mx) * (x - mx) }.reduce(0,+)
        guard den > 0 else { return nil }
        let slope = num / den
        let intercept = my - slope * mx     // y at x=0 (now)

        // R²
        let ssTot = zip(ys, ws).map { (y, w) in w * (y - my) * (y - my) }.reduce(0,+)
        let ssRes = zip(zip(xs, ys), ws).map { (xy, w) in
            let pred = slope * xy.0 + intercept
            return w * (xy.1 - pred) * (xy.1 - pred)
        }.reduce(0,+)
        let r2 = ssTot > 0 ? max(0, 1 - ssRes / ssTot) : 0

        var hit: Date? = nil
        if slope > 0.0001 {
            let secsUntil = (ceiling - intercept) / slope
            if secsUntil > 0 && secsUntil < (last.resetTime5h.timeIntervalSince(now) + 1) {
                hit = now.addingTimeInterval(secsUntil)
            }
        }

        // Build line points from now forward at 60s steps until hit (or window end).
        var line: [ForecastPoint] = []
        let endT = hit ?? last.resetTime5h
        var t = now
        while t < endT {
            let dx = t.timeIntervalSince(now)
            let pred = slope * dx + intercept
            line.append(.init(time: t, projectedFraction: min(1, pred / ceiling)))
            t.addTimeInterval(60)
        }
        return ForecastResult(slope: slope, intercept: intercept,
                              projectedHitTime: hit, line: line, rSquared: r2)
    }
}
```

- [ ] **Step 4: Run** → pass.
- [ ] **Step 5: Commit** `git commit -am "feat(forecast): LinearForecaster weighted regression"`

### Task 20: `BaselineForecaster` — per-hour median + IQR

**Files:**
- Create: `Sources/UsageCore/Forecast/BaselineForecaster.swift`
- Create: `Tests/UsageCoreTests/Forecast/BaselineForecasterTests.swift`

- [ ] **Step 1: Failing test**

```swift
import XCTest
@testable import UsageCore

final class BaselineForecasterTests: XCTestCase {
    func test_returns_24_buckets_for_24h_mode() {
        let now = Date()
        // 5 days of synthetic snapshots, one per hour
        var snaps: [UsageSnapshot] = []
        let cal = Calendar(identifier: .gregorian)
        for d in 1...5 {
            for h in 0..<24 {
                var c = cal.dateComponents([.year,.month,.day], from: now)
                c.day = (c.day ?? 1) - d; c.hour = h; c.minute = 0
                let t = cal.date(from: c)!
                snaps.append(UsageSnapshot(timestamp: t, plan: .pro,
                    used5h: h * 1000, ceiling5h: 100_000, resetTime5h: t,
                    usedWeek: 0, ceilingWeek: 1_000_000, resetTimeWeek: t,
                    sourceVersion: "json-v1", raw: Data()))
            }
        }
        let r = BaselineForecaster().baseline(snapshots: snaps, mode: .twentyFourHour, now: now)
        XCTAssertEqual(r.buckets.count, 24)
        // bucket 0 should have median ~0, bucket 23 should have median ~0.23
        XCTAssertEqual(r.buckets[0].median, 0, accuracy: 0.01)
        XCTAssertEqual(r.buckets[23].median, 0.23, accuracy: 0.01)
    }

    func test_returns_empty_when_history_too_short() {
        let r = BaselineForecaster().baseline(snapshots: [], mode: .twentyFourHour)
        XCTAssertTrue(r.buckets.isEmpty)
        XCTAssertEqual(r.note, .insufficientHistory)
    }
}
```

- [ ] **Step 2: Run** → fail.
- [ ] **Step 3: Implement**

```swift
import Foundation

public struct BaselineForecaster {
    public init() {}

    public enum Mode { case twentyFourHour, weekly }
    public enum BaselineNote { case ok, insufficientHistory }

    public struct Bucket: Equatable {
        public let key: Int             // hour 0..23 (24h) or hour-of-week 0..167 (1w)
        public let median: Double       // fraction of ceiling
        public let p25: Double
        public let p75: Double
    }

    public struct Baseline: Equatable {
        public let buckets: [Bucket]
        public let note: BaselineNote
    }

    public func baseline(snapshots: [UsageSnapshot],
                         mode: Mode,
                         now: Date = Date()) -> Baseline {
        // Need at least 3 distinct days of data.
        let cal = Calendar(identifier: .gregorian)
        let days = Set(snapshots.map { cal.startOfDay(for: $0.timestamp) }).count
        guard days >= 3 else { return .init(buckets: [], note: .insufficientHistory) }

        let bucketCount = (mode == .twentyFourHour) ? 24 : 168
        var grouped = [Int: [Double]]()
        for s in snapshots {
            let comps = cal.dateComponents([.weekday, .hour], from: s.timestamp)
            let key = (mode == .twentyFourHour)
                ? (comps.hour ?? 0)
                : ((comps.weekday ?? 1) - 1) * 24 + (comps.hour ?? 0)
            let frac = s.fraction5h
            grouped[key, default: []].append(frac)
        }
        let buckets = (0..<bucketCount).map { k -> Bucket in
            let arr = (grouped[k] ?? []).sorted()
            return Bucket(key: k, median: percentile(arr, 0.5),
                          p25: percentile(arr, 0.25), p75: percentile(arr, 0.75))
        }
        return .init(buckets: buckets, note: .ok)
    }

    private func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let i = Double(sorted.count - 1) * p
        let lo = Int(i.rounded(.down)); let hi = Int(i.rounded(.up))
        if lo == hi { return sorted[lo] }
        let frac = i - Double(lo)
        return sorted[lo] * (1 - frac) + sorted[hi] * frac
    }
}
```

- [ ] **Step 4: Run** → pass.
- [ ] **Step 5: Commit** `git commit -am "feat(forecast): BaselineForecaster per-hour percentiles"`

---

# Phase 7 — Polling controller

### Task 21: `PollingTimer` with jitter

**Files:**
- Create: `Sources/UsageCore/Polling/PollingTimer.swift`
- Create: `Tests/UsageCoreTests/Polling/PollingTimerTests.swift`

- [ ] **Step 1: Failing test**

```swift
import XCTest
@testable import UsageCore

final class PollingTimerTests: XCTestCase {
    func test_fires_at_expected_cadence() async {
        let timer = PollingTimer(interval: 0.2, jitter: 0)
        var ticks = 0
        let exp = expectation(description: "ticks")
        timer.onTick = { ticks += 1; if ticks == 3 { exp.fulfill() } }
        timer.start()
        await fulfillment(of: [exp], timeout: 2)
        timer.stop()
        XCTAssertEqual(ticks, 3)
    }
    func test_jitter_within_bounds() {
        let timer = PollingTimer(interval: 90, jitter: 10)
        for _ in 0..<100 {
            let next = timer.nextDelay()
            XCTAssertGreaterThanOrEqual(next, 80)
            XCTAssertLessThanOrEqual(next, 100)
        }
    }
}
```

- [ ] **Step 2: Run** → fail.
- [ ] **Step 3: Implement**

```swift
import Foundation

public final class PollingTimer {
    public var onTick: (() -> Void)?
    public let interval: TimeInterval
    public let jitter: TimeInterval
    private var task: Task<Void, Never>?

    public init(interval: TimeInterval, jitter: TimeInterval) {
        self.interval = interval; self.jitter = jitter
    }

    public func nextDelay() -> TimeInterval {
        guard jitter > 0 else { return interval }
        let r = Double.random(in: -jitter...jitter)
        return max(0, interval + r)
    }

    public func start() {
        stop()
        task = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.nextDelay() * 1_000_000_000))
                if Task.isCancelled { return }
                self.onTick?()
            }
        }
    }
    public func stop() { task?.cancel(); task = nil }
}
```

- [ ] **Step 4: Run** → pass.
- [ ] **Step 5: Commit** `git commit -am "feat(polling): PollingTimer with jitter"`

### Task 22: `UsageController` — orchestrates poll → store → derive → publish

**Files:**
- Create: `Sources/UsageCore/Polling/UsageController.swift`
- Create: `Tests/UsageCoreTests/Polling/UsageControllerTests.swift`

- [ ] **Step 1: Failing test (uses an in-memory scraper)**

```swift
import XCTest
import GRDB
@testable import UsageCore

final class UsageControllerTests: XCTestCase {
    func test_poll_inserts_snapshot_and_publishes_state() async throws {
        let dbq = try DatabaseQueue(); try Database.migrator.migrate(dbq)
        let snap = UsageSnapshot(timestamp: Date(), plan: .pro,
            used5h: 1, ceiling5h: 100, resetTime5h: Date().addingTimeInterval(3600),
            usedWeek: 1, ceilingWeek: 1000, resetTimeWeek: Date().addingTimeInterval(86400*5),
            sourceVersion: "fake", raw: Data())

        let controller = UsageController(
            scraper: FakeScraper(snap: snap),
            snapshots: SnapshotRepository(dbq: dbq, deviceID: "d1"),
            forecaster: LinearForecaster()
        )
        try await controller.pollOnce()
        XCTAssertNotNil(controller.state.latest)
        XCTAssertEqual(controller.state.latest?.used5h, 1)
    }
}
struct FakeScraper: UsageScraper {
    let sourceVersion = "fake"
    let snap: UsageSnapshot
    func fetchSnapshot() async throws -> UsageSnapshot { snap }
}
```

- [ ] **Step 2: Run** → fail.
- [ ] **Step 3: Implement**

```swift
import Foundation

@MainActor
public final class UsageController: ObservableObject {
    public struct State {
        public var latest: UsageSnapshot?
        public var forecast: ForecastResult?
        public var lastPollAt: Date?
        public var lastError: ScrapeError?
        public var consecutiveAuthFailures: Int = 0
    }

    @Published public private(set) var state = State()

    private let scraper: UsageScraper
    private let snapshots: SnapshotRepository
    private let forecaster: LinearForecaster

    public init(scraper: UsageScraper, snapshots: SnapshotRepository, forecaster: LinearForecaster) {
        self.scraper = scraper; self.snapshots = snapshots; self.forecaster = forecaster
    }

    public func pollOnce() async throws {
        do {
            let snap = try await scraper.fetchSnapshot()
            try snapshots.insert(snap)
            state.latest = snap
            state.lastPollAt = Date()
            state.lastError = nil
            state.consecutiveAuthFailures = 0
            let recent = try snapshots.fetchRecent(within: 3600)
            state.forecast = forecaster.forecast(snapshots: recent)
        } catch let e as ScrapeError {
            state.lastError = e
            if e.isAuthRelated { state.consecutiveAuthFailures += 1 }
            throw e
        }
    }
}
```

- [ ] **Step 4: Run** → pass.
- [ ] **Step 5: Commit** `git commit -am "feat(polling): UsageController orchestrates poll + state"`

---

# Phase 8 — Notification engine

### Task 23: `AlertEngine` — decides what to fire

**Files:**
- Create: `Sources/UsageCore/Notifications/AlertEngine.swift`
- Create: `Tests/UsageCoreTests/Notifications/AlertEngineTests.swift`

- [ ] **Step 1: Failing test**

```swift
import XCTest
@testable import UsageCore

final class AlertEngineTests: XCTestCase {
    func test_5h_forecast_fires_when_projected_hit_within_15min_and_R2_high() {
        let now = Date()
        let snap = UsageSnapshot(timestamp: now, plan: .pro,
            used5h: 80_000, ceiling5h: 100_000,
            resetTime5h: now.addingTimeInterval(3600 * 4),
            usedWeek: 0, ceilingWeek: 1_000_000,
            resetTimeWeek: now.addingTimeInterval(86400),
            sourceVersion: "fake", raw: Data())
        let f = ForecastResult(slope: 1, intercept: 80_000,
            projectedHitTime: now.addingTimeInterval(600), line: [], rSquared: 0.9)
        let engine = AlertEngine()
        let fires = engine.decide(snapshot: snap, forecast: f, alertState: NoOpAlertState(), settings: .default, now: now)
        XCTAssertTrue(fires.contains(.fiveHourForecast))
    }

    func test_week_90_fires_at_threshold() {
        let now = Date()
        let snap = UsageSnapshot(timestamp: now, plan: .pro,
            used5h: 0, ceiling5h: 100_000, resetTime5h: now,
            usedWeek: 900_000, ceilingWeek: 1_000_000, resetTimeWeek: now,
            sourceVersion: "fake", raw: Data())
        let fires = AlertEngine().decide(snapshot: snap, forecast: nil, alertState: NoOpAlertState(),
                                          settings: .default, now: now)
        XCTAssertTrue(fires.contains(.weekNinety))
    }

    func test_dedup_within_same_5h_window() {
        let now = Date()
        let snap = UsageSnapshot(timestamp: now, plan: .pro,
            used5h: 90_000, ceiling5h: 100_000,
            resetTime5h: now.addingTimeInterval(3600),
            usedWeek: 0, ceilingWeek: 1_000_000, resetTimeWeek: now,
            sourceVersion: "fake", raw: Data())
        let f = ForecastResult(slope: 1, intercept: 90_000,
            projectedHitTime: now.addingTimeInterval(300), line: [], rSquared: 0.9)
        let state = StubAlertState()
        state.firedAt[.fiveHourForecast] = snap.currentWindowStart5h.addingTimeInterval(60)
        let fires = AlertEngine().decide(snapshot: snap, forecast: f, alertState: state, settings: .default, now: now)
        XCTAssertFalse(fires.contains(.fiveHourForecast))
    }
}

class StubAlertState: AlertStateReader {
    var firedAt: [AlertKind: Date] = [:]
    var snoozedUntil: [AlertKind: Date] = [:]
    func lastFired(_ k: AlertKind) -> Date? { firedAt[k] }
    func snoozedUntil(_ k: AlertKind) -> Date? { snoozedUntil[k] }
}
class NoOpAlertState: AlertStateReader {
    func lastFired(_ k: AlertKind) -> Date? { nil }
    func snoozedUntil(_ k: AlertKind) -> Date? { nil }
}
```

- [ ] **Step 2: Run** → fail.
- [ ] **Step 3: Implement**

```swift
import Foundation

public protocol AlertStateReader {
    func lastFired(_ kind: AlertKind) -> Date?
    func snoozedUntil(_ kind: AlertKind) -> Date?
}

public struct AlertSettings {
    public var enabled: Set<AlertKind>
    public var quietHoursStartMin: Int  // minutes since midnight
    public var quietHoursEndMin: Int
    public static let `default` = AlertSettings(
        enabled: Set(AlertKind.allCases),
        quietHoursStartMin: 22 * 60,
        quietHoursEndMin: 8 * 60
    )
}

public struct AlertEngine {
    public init() {}

    public func decide(snapshot s: UsageSnapshot,
                       forecast f: ForecastResult?,
                       alertState st: AlertStateReader,
                       settings: AlertSettings,
                       now: Date) -> Set<AlertKind> {
        var fires: Set<AlertKind> = []

        // 5h-forecast
        if settings.enabled.contains(.fiveHourForecast),
           let f, !f.isLowConfidence, let hit = f.projectedHitTime,
           hit.timeIntervalSince(now) <= 15 * 60,
           !alreadyFiredInWindow(.fiveHourForecast, windowStart: s.currentWindowStart5h, st: st) {
            fires.insert(.fiveHourForecast)
        }

        // 5h-hit
        if settings.enabled.contains(.fiveHourHit),
           s.used5h >= s.ceiling5h,
           !alreadyFiredInWindow(.fiveHourHit, windowStart: s.currentWindowStart5h, st: st) {
            fires.insert(.fiveHourHit)
        }

        // weekly thresholds
        if settings.enabled.contains(.weekNinety),
           s.fractionWeek >= 0.9,
           !alreadyFiredInWeek(.weekNinety, weekStart: s.resetTimeWeek.addingTimeInterval(-7*86400), st: st) {
            fires.insert(.weekNinety)
        }
        if settings.enabled.contains(.weekHundred),
           s.usedWeek >= s.ceilingWeek,
           !alreadyFiredInWeek(.weekHundred, weekStart: s.resetTimeWeek.addingTimeInterval(-7*86400), st: st) {
            fires.insert(.weekHundred)
        }

        // honor snoozes
        fires = fires.filter { (st.snoozedUntil($0) ?? .distantPast) < now }

        return fires
    }

    private func alreadyFiredInWindow(_ k: AlertKind, windowStart: Date, st: AlertStateReader) -> Bool {
        guard let last = st.lastFired(k) else { return false }
        return last >= windowStart
    }
    private func alreadyFiredInWeek(_ k: AlertKind, weekStart: Date, st: AlertStateReader) -> Bool {
        guard let last = st.lastFired(k) else { return false }
        return last >= weekStart
    }

    public func isQuietHours(_ now: Date, settings: AlertSettings, calendar: Calendar = .init(identifier: .gregorian)) -> Bool {
        let comps = calendar.dateComponents([.hour, .minute], from: now)
        let m = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let start = settings.quietHoursStartMin, end = settings.quietHoursEndMin
        if start <= end { return m >= start && m < end }
        return m >= start || m < end                 // crosses midnight
    }
}
```

- [ ] **Step 4: Run** → pass.
- [ ] **Step 5: Commit** `git commit -am "feat(notifications): AlertEngine decision logic"`

### Task 24: `NotificationDispatcher` — delivers via UNUserNotificationCenter

**Files:**
- Create: `Sources/UsageCore/Notifications/NotificationDispatcher.swift`

- [ ] **Step 1: Implement** (no automated test — relies on real notification center; tested manually)

```swift
import Foundation
import UserNotifications

public struct NotificationDispatcher {
    public init() {}

    public func requestAuthorization() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        return granted
    }

    public func deliver(_ kind: AlertKind, snapshot s: UsageSnapshot, forecast f: ForecastResult?) async {
        let center = UNUserNotificationCenter.current()
        let req = makeRequest(kind: kind, snapshot: s, forecast: f)
        try? await center.add(req)
    }

    private func makeRequest(kind: AlertKind, snapshot s: UsageSnapshot, forecast f: ForecastResult?) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        switch kind {
        case .fiveHourForecast:
            content.title = "Approaching 5h limit"
            if let h = f?.projectedHitTime {
                let df = DateFormatter(); df.timeStyle = .short
                content.body = "At your current rate you'll hit the limit at \(df.string(from: h))."
            } else { content.body = "Slow down or risk hitting the 5h limit." }
        case .fiveHourHit:
            content.title = "5h limit reached"; content.body = "Your 5h window is exhausted."
        case .weekNinety:
            content.title = "Weekly usage at 90%"; content.body = "You've used 90% of your weekly cap."
        case .weekHundred:
            content.title = "Weekly limit reached"; content.body = "Resets at \(s.resetTimeWeek)."
        case .authExpired:
            content.title = "Claude.ai login expired"; content.body = "Tap to re-login."
        case .scrapeBroken:
            content.title = "Source format changed"; content.body = "Update Claude Usage to restore tracking."
        }
        content.sound = .default
        return UNNotificationRequest(identifier: kind.rawValue + "-\(Int(Date().timeIntervalSince1970))",
                                      content: content, trigger: nil)
    }
}
```

- [ ] **Step 2: Build** `swift build` → no errors.
- [ ] **Step 3: Commit** `git commit -am "feat(notifications): NotificationDispatcher with UN messages"`

---

# Phase 9 — CloudKit sync

### Task 25: `SyncRecordMapper` — UsageSnapshot ↔ CKRecord

**Files:**
- Create: `Sources/UsageCore/Sync/SyncRecordMapper.swift`
- Create: `Tests/UsageCoreTests/Sync/SyncRecordMapperTests.swift`

- [ ] **Step 1: Failing test**

```swift
import XCTest
import CloudKit
@testable import UsageCore

final class SyncRecordMapperTests: XCTestCase {
    func test_roundtrip_preserves_fields() {
        let now = Date()
        let s = UsageSnapshot(timestamp: now, plan: .pro,
            used5h: 1, ceiling5h: 100, resetTime5h: now,
            usedWeek: 5, ceilingWeek: 1000, resetTimeWeek: now,
            sourceVersion: "json-v1", raw: Data())
        let rec = SyncRecordMapper.toRecord(s, deviceID: "d1")
        XCTAssertEqual(rec.recordID.recordName, "d1-\(Int(now.timeIntervalSince1970))")
        let back = SyncRecordMapper.fromRecord(rec)!
        XCTAssertEqual(back.used5h, 1)
        XCTAssertEqual(back.plan, .pro)
    }
}
```

- [ ] **Step 2: Run** → fail.
- [ ] **Step 3: Implement**

```swift
import Foundation
import CloudKit

public enum SyncRecordMapper {
    public static let recordType = "UsageSnapshot"

    public static func toRecord(_ s: UsageSnapshot, deviceID: String) -> CKRecord {
        let id = CKRecord.ID(recordName: "\(deviceID)-\(Int(s.timestamp.timeIntervalSince1970))")
        let r = CKRecord(recordType: recordType, recordID: id)
        r["device_id"] = deviceID
        r["ts"] = s.timestamp
        r["plan"] = s.plan.displayName
        r["used_5h"] = s.used5h; r["ceiling_5h"] = s.ceiling5h; r["reset_5h"] = s.resetTime5h
        r["used_week"] = s.usedWeek; r["ceiling_week"] = s.ceilingWeek; r["reset_week"] = s.resetTimeWeek
        r["source_version"] = s.sourceVersion
        return r
    }

    public static func fromRecord(_ r: CKRecord) -> UsageSnapshot? {
        guard let ts = r["ts"] as? Date,
              let plan = r["plan"] as? String,
              let u5 = r["used_5h"] as? Int, let c5 = r["ceiling_5h"] as? Int, let r5 = r["reset_5h"] as? Date,
              let uw = r["used_week"] as? Int, let cw = r["ceiling_week"] as? Int, let rw = r["reset_week"] as? Date,
              let v  = r["source_version"] as? String else { return nil }
        return UsageSnapshot(timestamp: ts, plan: Plan(rawString: plan),
            used5h: u5, ceiling5h: c5, resetTime5h: r5,
            usedWeek: uw, ceilingWeek: cw, resetTimeWeek: rw,
            sourceVersion: v, raw: Data())
    }
}
```

- [ ] **Step 4: Run** → pass.
- [ ] **Step 5: Commit** `git commit -am "feat(sync): SyncRecordMapper round-trips snapshots"`

### Task 26: `CloudKitSync` — debounced upload + fetch since timestamp

**Files:**
- Create: `Sources/UsageCore/Sync/CloudKitSync.swift`

- [ ] **Step 1: Implement** (CloudKit requires real container; integration-test manually)

```swift
import Foundation
import CloudKit

public final class CloudKitSync {
    public let container: CKContainer
    public let database: CKDatabase
    public let deviceID: String

    public init(containerIdentifier: String, deviceID: String) {
        self.container = CKContainer(identifier: containerIdentifier)
        self.database = container.privateCloudDatabase
        self.deviceID = deviceID
    }

    public func upload(_ snapshots: [UsageSnapshot]) async throws {
        let records = snapshots.map { SyncRecordMapper.toRecord($0, deviceID: deviceID) }
        let op = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
        op.savePolicy = .ifServerRecordUnchanged
        op.qualityOfService = .utility
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            op.modifyRecordsResultBlock = { result in
                switch result {
                case .success: cont.resume()
                case .failure(let e): cont.resume(throwing: e)
                }
            }
            database.add(op)
        }
    }

    public func fetchSince(_ ts: Date) async throws -> [UsageSnapshot] {
        let pred = NSPredicate(format: "ts > %@", ts as NSDate)
        let q = CKQuery(recordType: SyncRecordMapper.recordType, predicate: pred)
        q.sortDescriptors = [NSSortDescriptor(key: "ts", ascending: true)]
        let (results, _) = try await database.records(matching: q)
        return results.compactMap { (_, r) in
            switch r {
            case .success(let rec): return SyncRecordMapper.fromRecord(rec)
            case .failure: return nil
            }
        }
    }
}
```

- [ ] **Step 2: Build** → no errors.
- [ ] **Step 3: Commit** `git commit -am "feat(sync): CloudKitSync upload/fetchSince"`

### Task 27: `UsageController` integration — debounce + sync hook

**Files:**
- Modify: `Sources/UsageCore/Polling/UsageController.swift`
- Modify: `Tests/UsageCoreTests/Polling/UsageControllerTests.swift`

- [ ] **Step 1: Failing test for "sync invoked at most once per 5min"**

```swift
func test_sync_called_at_most_once_per_300s() async throws {
    let dbq = try DatabaseQueue(); try Database.migrator.migrate(dbq)
    let snap = UsageSnapshot(timestamp: Date(), plan: .pro,
        used5h: 1, ceiling5h: 100, resetTime5h: Date(),
        usedWeek: 1, ceilingWeek: 1000, resetTimeWeek: Date(),
        sourceVersion: "fake", raw: Data())
    let sync = SpySync()
    let controller = UsageController(
        scraper: FakeScraper(snap: snap),
        snapshots: SnapshotRepository(dbq: dbq, deviceID: "d1"),
        forecaster: LinearForecaster(),
        sync: sync,
        syncIntervalSeconds: 1) // shorten for test
    try await controller.pollOnce()
    try await controller.pollOnce()
    try await Task.sleep(nanoseconds: 1_200_000_000)
    try await controller.pollOnce()
    XCTAssertEqual(sync.calls, 2, "first poll + post-1s")
}
final class SpySync: CloudKitSyncing {
    var calls = 0
    func uploadPending(snapshots: [UsageSnapshot]) async throws { calls += 1 }
}
```

- [ ] **Step 2: Run** → fail.
- [ ] **Step 3: Implement** — extract `CloudKitSyncing` protocol, add debounce timer to controller

```swift
public protocol CloudKitSyncing {
    func uploadPending(snapshots: [UsageSnapshot]) async throws
}

extension CloudKitSync: CloudKitSyncing {
    public func uploadPending(snapshots: [UsageSnapshot]) async throws {
        try await upload(snapshots)
    }
}

@MainActor
public final class UsageController: ObservableObject {
    // ... (existing fields)
    private let sync: CloudKitSyncing?
    private let syncIntervalSeconds: TimeInterval
    private var lastSyncedAt: Date?
    private var pendingForSync: [UsageSnapshot] = []

    public init(scraper: UsageScraper, snapshots: SnapshotRepository,
                forecaster: LinearForecaster, sync: CloudKitSyncing? = nil,
                syncIntervalSeconds: TimeInterval = 300) {
        self.scraper = scraper; self.snapshots = snapshots
        self.forecaster = forecaster; self.sync = sync
        self.syncIntervalSeconds = syncIntervalSeconds
    }

    public func pollOnce() async throws {
        // ... (existing body) ...
        pendingForSync.append(snap)
        await maybeSync()
    }

    private func maybeSync() async {
        guard let sync = sync else { return }
        let now = Date()
        if let last = lastSyncedAt, now.timeIntervalSince(last) < syncIntervalSeconds { return }
        let batch = pendingForSync
        pendingForSync.removeAll()
        do { try await sync.uploadPending(snapshots: batch) ; lastSyncedAt = now }
        catch { pendingForSync = batch + pendingForSync /* retry next time */ }
    }
}
```

- [ ] **Step 4: Run** → pass.
- [ ] **Step 5: Commit** `git commit -am "feat(sync): debounce CloudKit upload in UsageController"`

---

# Phase 10 — macOS app shell

### Task 28: Add macOS app target in Xcode

**Files:**
- Create: `Apps/ClaudeUsageMac/ClaudeUsageMacApp.swift`
- Create: `Apps/ClaudeUsageMac/Info.plist`

- [ ] **Step 1:** In Xcode, **File → New → Target → macOS App**, name `ClaudeUsageMac`, interface SwiftUI, life cycle SwiftUI App, language Swift. Drag the local `UsageCore` package into the target's "Frameworks, Libraries, and Embedded Content."
- [ ] **Step 2:** Open `Info.plist` → set `Application is agent (UIElement)` (`LSUIElement`) to `YES`.
- [ ] **Step 3:** Replace generated `ClaudeUsageMacApp.swift`:

```swift
import SwiftUI
import UsageCore

@main
struct ClaudeUsageMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Settings { EmptyView() }     // suppress default WindowGroup
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: StatusItemController!

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = StatusItemController()
    }
}
```

- [ ] **Step 4:** Build the macOS scheme. Expected: app launches, no Dock icon, no visible UI yet, no menu bar item (StatusItemController is empty).
- [ ] **Step 5:** Commit `git commit -am "feat(mac): bootstrap LSUIElement macOS app"`

### Task 29: `StatusItemController` — render `⌬ ⏳`

**Files:**
- Create: `Apps/ClaudeUsageMac/MenuBar/StatusItemController.swift`

- [ ] **Step 1: Implement skeleton**

```swift
import AppKit

final class StatusItemController {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    init() {
        if let button = item.button {
            button.title = "⌬ ⏳"
            button.toolTip = "Claude Usage — initializing"
        }
    }

    func setText(_ s: String, tooltip: String) {
        item.button?.title = s
        item.button?.toolTip = tooltip
    }
}
```

- [ ] **Step 2:** Build + run macOS scheme. Verify menu bar shows `⌬ ⏳`.
- [ ] **Step 3:** Commit `git commit -am "feat(mac): StatusItemController shows initializing state"`

### Task 30: Wire `UsageController` into macOS app

**Files:**
- Modify: `Apps/ClaudeUsageMac/ClaudeUsageMacApp.swift`
- Create: `Apps/ClaudeUsageMac/AppContext.swift`

- [ ] **Step 1: Implement `AppContext`** (lazily holds the ObjectGraph)

```swift
import Foundation
import GRDB
import UsageCore

@MainActor
final class AppContext {
    let dbq: DatabaseQueue
    let snapshots: SnapshotRepository
    let alertState: AlertStateRepository
    let settings: SettingsRepository
    let keychain: KeychainStore
    let deviceID: String
    let cookieStore: CookiePackageStore
    var controller: UsageController?
    var pollingTimer: PollingTimer?

    init() throws {
        let dir = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("ClaudeUsage", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.dbq = try Database.openOnDisk(at: dir.appendingPathComponent("usage.db"))
        self.keychain = KeychainStore()
        self.deviceID = try DeviceID.getOrCreate(in: keychain)
        self.snapshots = SnapshotRepository(dbq: dbq, deviceID: deviceID)
        self.alertState = AlertStateRepository(dbq: dbq)
        self.settings = SettingsRepository(dbq: dbq)
        self.cookieStore = CookiePackageStore(keychain: keychain, deviceID: deviceID)
    }
}
```

- [ ] **Step 2: Add a `LoginWindowController` stub** so Task 30 compiles standalone. The real implementation arrives in Task 31, which replaces this file.

`Apps/ClaudeUsageMac/Auth/LoginWindowController.swift`:

```swift
import AppKit
import UsageCore

@MainActor
enum LoginWindowController {
    /// STUB — Task 31 replaces this with a real WKWebView-based login flow.
    static func show(ctx: AppContext, onComplete: @escaping () -> Void) {
        onComplete()
    }
}
```

- [ ] **Step 3: Modify `AppDelegate`** to construct `AppContext`, kick off login or polling:

```swift
final class AppDelegate: NSObject, NSApplicationDelegate {
    var ctx: AppContext!
    var statusItem: StatusItemController!

    func applicationDidFinishLaunching(_ n: Notification) {
        do {
            ctx = try AppContext()
            statusItem = StatusItemController()
            if (try? ctx.cookieStore.load()) == nil {
                LoginWindowController.show(ctx: ctx, onComplete: { [weak self] in
                    self?.startPolling()
                })
            } else {
                startPolling()
            }
        } catch {
            statusItem = StatusItemController()
            statusItem.setText("⌬ ⚠", tooltip: "Init failed: \(error)")
        }
    }

    private func startPolling() {
        Task { @MainActor in
            guard let pkg = try? ctx.cookieStore.load() else { return }
            let endpoint = EndpointConfig(jsonEndpoint: nil)  // discovered at runtime; M2 pending
            let factory = ScraperFactory(config: endpoint, cookies: pkg)
            ctx.controller = UsageController(
                scraper: factory.current(),
                snapshots: ctx.snapshots,
                forecaster: LinearForecaster(),
                sync: nil)
            let timer = PollingTimer(interval: 90, jitter: 10)
            timer.onTick = { [weak self] in Task { @MainActor in await self?.tick() } }
            timer.start()
            ctx.pollingTimer = timer
            await tick()  // immediate first poll
        }
    }

    @MainActor
    private func tick() async {
        guard let c = ctx.controller else { return }
        do { try await c.pollOnce() ; render() }
        catch let e as ScrapeError {
            statusItem.setText("⌬ ⚠", tooltip: "\(e)")
        } catch { statusItem.setText("⌬ ⚠", tooltip: "\(error)") }
    }

    private func render() {
        guard let snap = ctx.controller?.state.latest else {
            statusItem.setText("⌬ —", tooltip: "No data")
            return
        }
        let pct = Int(snap.fraction5h * 100)
        statusItem.setText("⌬ \(pct)%",
            tooltip: "5h: \(pct)% • Week: \(Int(snap.fractionWeek*100))%")
    }
}
```

- [ ] **Step 4:** Build. Expected: launches in `⌬ ⏳`. With the Task 30 stub, the login "succeeds" immediately (no UI). Polling will then start with empty cookies → first poll fails. That's expected — Task 31 replaces the stub with a real login window.
- [ ] **Step 5:** Commit `git commit -am "feat(mac): wire AppContext + UsageController to status item"`

---

# Phase 11 — macOS login

### Task 31: `LoginWindowController` + `LoginWebView`

**Files:**
- Create: `Apps/ClaudeUsageMac/Auth/LoginWindowController.swift`
- Create: `Apps/ClaudeUsageMac/Auth/LoginWebView.swift`

- [ ] **Step 1: Implement `LoginWindowController`**

```swift
import AppKit
import WebKit
import UsageCore

@MainActor
final class LoginWindowController {
    private static var currentWindow: NSWindow?

    static func show(ctx: AppContext, onComplete: @escaping () -> Void) {
        let win = NSWindow(contentRect: .init(x: 0, y: 0, width: 500, height: 700),
                           styleMask: [.titled, .closable, .miniaturizable],
                           backing: .buffered, defer: false)
        win.title = "Sign in to claude.ai"
        win.center()

        let view = LoginWebView(onSuccess: { pkg in
            try? ctx.cookieStore.save(pkg)
            DispatchQueue.main.async {
                win.close()
                currentWindow = nil
                onComplete()
            }
        })
        win.contentView = view
        win.makeKeyAndOrderFront(nil)
        currentWindow = win
    }
}
```

- [ ] **Step 2: Implement `LoginWebView`**

```swift
import AppKit
import WebKit
import UsageCore

final class LoginWebView: NSView, WKNavigationDelegate {
    let webView: WKWebView
    let onSuccess: (CookiePackage) -> Void
    private var didFire = false

    init(onSuccess: @escaping (CookiePackage) -> Void) {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        self.webView = WKWebView(frame: .zero, configuration: cfg)
        self.onSuccess = onSuccess
        super.init(frame: .zero)
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        webView.navigationDelegate = self
        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
    }

    required init?(coder: NSCoder) { fatalError() }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url else { return }
        // Successful login redirects away from /login to /chats or /new etc.
        if !didFire, !url.path.contains("/login"), url.host?.contains("claude.ai") == true {
            didFire = true
            Task {
                let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
                webView.evaluateJavaScript("navigator.userAgent") { value, _ in
                    let ua = (value as? String) ?? "Mozilla/5.0"
                    let pkg = CookieReader.package(from: cookies, userAgent: ua)
                    self.onSuccess(pkg)
                }
            }
        }
    }
}
```

- [ ] **Step 3:** Build + run. Sign in. Expected: window closes, polling begins, menu bar updates from `⌬ ⏳` → `⌬ N%` (or `⌬ ⚠` if endpoint not yet configured — that's expected for M1; `⌬ N%` requires Task 32 endpoint discovery).
- [ ] **Step 4:** Commit `git commit -am "feat(mac): WKWebView login flow stores cookies"`

### Task 32: **Endpoint discovery** (manual)

**Files:**
- Modify: `Apps/ClaudeUsageMac/AppContext.swift`

- [ ] **Step 1: Open Safari/Chrome, sign into claude.ai, navigate to `https://claude.ai/settings/usage`. Open DevTools → Network tab. Reload the page.**
- [ ] **Step 2: Identify the XHR/fetch that returns usage data.** Record:
  - Full URL (likely under `/api/...`)
  - HTTP method
  - Sample response body (paste into a dev note)
- [ ] **Step 3: If the response shape differs from what `JSONUsageScraper.Response` expects, update `JSONUsageScraper.Response` Codable to match.** Re-run `JSONUsageScraperTests` with a new fixture matching the real shape.
- [ ] **Step 4: Wire the endpoint into `AppContext`.** Replace `EndpointConfig(jsonEndpoint: nil)` in `AppDelegate.startPolling()` with the discovered URL. Persist it to `SettingsRepository` so future runs reuse it.
- [ ] **Step 5: Run macOS app end-to-end.** Sign in, watch menu bar for ~3 minutes. Expected: menu bar shows `⌬ N%` reflecting real usage; updates every 90s.
- [ ] **Step 6: Commit** `git commit -am "feat(scraping): wire discovered claude.ai usage endpoint"`

### Task 33: Hidden challenge view for `cf_clearance` refresh

**Files:**
- Create: `Apps/ClaudeUsageMac/Auth/HiddenChallengeView.swift`
- Modify: `AppDelegate.tick()` to trigger refresh on `.cloudflareChallenge`

- [ ] **Step 1:** Implement `HiddenChallengeView` (1×1 pt WKWebView that loads `https://claude.ai/`):

```swift
import AppKit
import WebKit
import UsageCore

@MainActor
final class HiddenChallengeView {
    static func refreshClearance(into store: CookiePackageStore, currentDeviceID: String) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let cfg = WKWebViewConfiguration()
            let webView = WKWebView(frame: .init(x: 0, y: 0, width: 1, height: 1), configuration: cfg)
            // Hold a reference to keep the view alive
            var holder: WKWebView? = webView
            class Delegate: NSObject, WKNavigationDelegate {
                let onDone: (Bool) -> Void
                let store: CookiePackageStore
                init(_ store: CookiePackageStore, _ onDone: @escaping (Bool) -> Void) {
                    self.store = store; self.onDone = onDone
                }
                func webView(_ wv: WKWebView, didFinish nav: WKNavigation!) {
                    Task {
                        let cookies = await wv.configuration.websiteDataStore.httpCookieStore.allCookies()
                        wv.evaluateJavaScript("navigator.userAgent") { v, _ in
                            let ua = (v as? String) ?? "Mozilla/5.0"
                            let new = CookieReader.package(from: cookies, userAgent: ua)
                            if let existing = try? self.store.load() {
                                var merged = existing
                                merged.cfClearance = new.cfClearance ?? merged.cfClearance
                                merged.cfBm = new.cfBm ?? merged.cfBm
                                merged.userAgent = ua
                                try? self.store.save(merged)
                                self.onDone(merged.cfClearance != nil)
                            } else { self.onDone(false) }
                        }
                    }
                }
                func webView(_ wv: WKWebView, didFail nav: WKNavigation!, withError error: Error) { onDone(false) }
            }
            let del = Delegate(store) { ok in holder = nil; cont.resume(returning: ok) }
            webView.navigationDelegate = del
            objc_setAssociatedObject(webView, "del", del, .OBJC_ASSOCIATION_RETAIN)
            webView.load(URLRequest(url: URL(string: "https://claude.ai/")!))
        }
    }
}
```

- [ ] **Step 2:** Modify `tick()` to recover on Cloudflare challenge:

```swift
@MainActor
private func tick() async {
    guard let c = ctx.controller else { return }
    do { try await c.pollOnce(); render() }
    catch let e as ScrapeError {
        if e.requiresWebViewRefresh {
            let ok = await HiddenChallengeView.refreshClearance(into: ctx.cookieStore, currentDeviceID: ctx.deviceID)
            if ok { try? await c.pollOnce(); render() }
            else { statusItem.setText("⌬ ⚠", tooltip: "Cloudflare challenge unrecoverable") }
        } else if e.isAuthRelated {
            statusItem.setText("⌬ ⚠", tooltip: "Session expired — open app to re-login")
        } else {
            statusItem.setText("⌬ ⚠", tooltip: "\(e)")
        }
    } catch { statusItem.setText("⌬ ⚠", tooltip: "\(error)") }
}
```

- [ ] **Step 3:** Manual verify: clear cookies in Keychain, run, sign in, observe recovery flow on next forced challenge (hard to reproduce on demand; document in a `tests/manual/cloudflare-challenge.md`).
- [ ] **Step 4:** Commit `git commit -am "feat(mac): silent cf_clearance refresh via hidden WKWebView"`

---

# Phase 12 — macOS popover

### Task 34: `PopoverController` — toggle on click

**Files:**
- Create: `Apps/ClaudeUsageMac/Popover/PopoverController.swift`
- Modify: `Apps/ClaudeUsageMac/MenuBar/StatusItemController.swift`

- [ ] **Step 1:** Implement controller:

```swift
import AppKit
import SwiftUI
import UsageCore

@MainActor
final class PopoverController {
    let popover = NSPopover()
    let ctx: AppContext

    init(ctx: AppContext) {
        self.ctx = ctx
        popover.contentSize = NSSize(width: 340, height: 420)
        popover.behavior = .transient
        let host = NSHostingController(rootView: PopoverRootView().environmentObject(ctx.controller!))
        popover.contentViewController = host
    }

    func toggle(from anchor: NSStatusBarButton) {
        if popover.isShown { popover.performClose(nil) }
        else { popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY) }
    }
}
```

- [ ] **Step 2:** Wire status item click:

```swift
final class StatusItemController {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var onClick: (() -> Void)?

    init() {
        if let button = item.button {
            button.title = "⌬ ⏳"
            button.target = self; button.action = #selector(buttonClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }
    @objc private func buttonClicked() { onClick?() }
    func setText(_ s: String, tooltip: String) {
        item.button?.title = s; item.button?.toolTip = tooltip
    }
}
```

- [ ] **Step 3:** In `AppDelegate.startPolling()` after the controller is built, set: `statusItem.onClick = { [weak self] in self?.popover?.toggle(from: self!.statusItem.item.button!) }` and store `popover = PopoverController(ctx: ctx)`.
- [ ] **Step 4:** Commit `git commit -am "feat(mac): popover toggle wired to status item"`

### Task 35: `GaugeCardView` — single-gauge SwiftUI view

**Files:**
- Create: `Apps/ClaudeUsageMac/Popover/GaugeCardView.swift`

- [ ] **Step 1:** Implement:

```swift
import SwiftUI

struct GaugeCardView: View {
    let label: String
    let percent: Double          // 0..1
    let resetCaption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("\(Int(percent * 100))%")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
            ProgressView(value: percent)
                .progressViewStyle(.linear)
                .tint(color(for: percent))
            Text(resetCaption)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func color(for p: Double) -> Color {
        if p >= 0.9 { return .red }
        if p >= 0.75 { return .orange }
        return .green
    }
}
```

- [ ] **Step 2:** Commit `git commit -am "feat(mac): GaugeCardView"`

### Task 36: `ChartView` — Swift Charts with timeframe state

**Files:**
- Create: `Apps/ClaudeUsageMac/Popover/ChartView.swift`
- Create: `Apps/ClaudeUsageMac/Popover/TimeframePicker.swift`

- [ ] **Step 1:** `TimeframePicker.swift`:

```swift
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
```

- [ ] **Step 2:** `ChartView.swift`:

```swift
import SwiftUI
import Charts
import UsageCore

struct ChartView: View {
    let snapshots: [UsageSnapshot]
    let forecast: ForecastResult?
    let timeframe: Timeframe

    var body: some View {
        let cutoff = Date().addingTimeInterval(-timeframe.seconds)
        let visible = snapshots.filter { $0.timestamp >= cutoff }
        Chart {
            ForEach(visible, id: \.timestamp) { s in
                LineMark(
                    x: .value("t", s.timestamp),
                    y: .value("pct", s.fraction5h * 100))
                .foregroundStyle(.green)
            }
            if let f = forecast {
                ForEach(Array(f.line.enumerated()), id: \.offset) { _, p in
                    LineMark(
                        x: .value("t", p.time),
                        y: .value("pct", p.projectedFraction * 100))
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                }
            }
        }
        .chartYScale(domain: 0...100)
        .frame(height: 90)
    }
}
```

- [ ] **Step 3:** Commit `git commit -am "feat(mac): ChartView + TimeframePicker"`

### Task 37: `ForecastCaptionView` and `FooterView`

**Files:**
- Create: `Apps/ClaudeUsageMac/Popover/ForecastCaptionView.swift`
- Create: `Apps/ClaudeUsageMac/Popover/FooterView.swift`

- [ ] **Step 1:** `ForecastCaptionView`:

```swift
import SwiftUI
import UsageCore

struct ForecastCaptionView: View {
    let forecast: ForecastResult?

    var body: some View {
        if let f = forecast, let hit = f.projectedHitTime {
            let df: DateFormatter = { let d = DateFormatter(); d.timeStyle = .short; return d }()
            let label = f.isLowConfidence
                ? "⏱ ~\(df.string(from: hit)) (low confidence)"
                : "⏱ likely full at \(df.string(from: hit))"
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        } else if forecast != nil {
            Text("⏱ stable, no projection").font(.system(size: 11)).foregroundStyle(.secondary)
        } else {
            Text("⏱ Building forecast…").font(.system(size: 11)).foregroundStyle(.tertiary)
        }
    }
}
```

- [ ] **Step 2:** `FooterView`:

```swift
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
            Button("Refresh", action: onRefresh)
                .buttonStyle(.borderless)
                .font(.system(size: 11))
        }
    }

    private var footerText: String {
        guard let t = lastPollAt else { return "Never polled" }
        let s = Int(Date().timeIntervalSince(t))
        if s < 60 { return "Last poll: \(s)s ago" }
        if s < 3600 { return "Last poll: \(s/60)m ago" }
        return "Last poll: \(s/3600)h ago"
    }
    private var footerColor: Color {
        guard let t = lastPollAt else { return .red }
        let s = Date().timeIntervalSince(t)
        if s < 120 { return .green }
        if s < 600 { return .orange }
        return .red
    }
}
```

- [ ] **Step 3:** Commit `git commit -am "feat(mac): forecast caption + footer"`

### Task 38: `PopoverRootView` — composes everything

**Files:**
- Create: `Apps/ClaudeUsageMac/Popover/PopoverRootView.swift`

- [ ] **Step 1:** Implement:

```swift
import SwiftUI
import GRDB
import UsageCore

struct PopoverRootView: View {
    @EnvironmentObject var controller: UsageController
    @State private var timeframe: Timeframe = .oneHour
    @State private var snapshots: [UsageSnapshot] = []
    @State private var refreshTick = 0       // forces rerender

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CLAUDE USAGE")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(controller.state.latest?.plan.displayName ?? "—")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                GaugeCardView(label: "5h",
                    percent: controller.state.latest?.fraction5h ?? 0,
                    resetCaption: resetCaption(controller.state.latest?.resetTime5h))
                GaugeCardView(label: "Week",
                    percent: controller.state.latest?.fractionWeek ?? 0,
                    resetCaption: weeklyResetCaption(controller.state.latest?.resetTimeWeek))
            }

            TimeframePicker(selection: $timeframe)
            ChartView(snapshots: snapshots, forecast: controller.state.forecast, timeframe: timeframe)
            if timeframe == .oneHour || timeframe == .eightHour {
                ForecastCaptionView(forecast: controller.state.forecast)
            }
            FooterView(lastPollAt: controller.state.lastPollAt, onRefresh: {
                Task { try? await controller.pollOnce() }
            })
        }
        .padding(12)
        .frame(width: 340)
        .onAppear { refreshSnapshots() }
        .onChange(of: timeframe) { refreshSnapshots() }
        .onChange(of: controller.state.lastPollAt) { refreshSnapshots() }
    }

    private func refreshSnapshots() {
        // Pull from injected SnapshotRepository via global AppContext
        // Simplification: snapshots provided through UsageController later.
        snapshots = controller.state.latest.map { [$0] } ?? []
    }

    private func resetCaption(_ d: Date?) -> String {
        guard let d else { return "—" }
        let s = max(0, Int(d.timeIntervalSinceNow))
        return "resets in \(s/3600)h \((s/60)%60)m"
    }
    private func weeklyResetCaption(_ d: Date?) -> String {
        guard let d else { return "—" }
        let df = DateFormatter(); df.dateFormat = "E"; return "resets \(df.string(from: d))"
    }
}
```

- [ ] **Step 2:** Build + open popover. Verify gauges show values.
- [ ] **Step 3:** Commit `git commit -am "feat(mac): popover root view composed"`

### Task 39: Expose snapshots history in `UsageController`

**Files:**
- Modify: `Sources/UsageCore/Polling/UsageController.swift`
- Modify: `Apps/ClaudeUsageMac/Popover/PopoverRootView.swift`

- [ ] **Step 1: Failing test** — controller exposes snapshots within timeframe:

```swift
func test_snapshots_within_timeframe() async throws {
    let dbq = try DatabaseQueue(); try Database.migrator.migrate(dbq)
    let snap = UsageSnapshot(timestamp: Date(), plan: .pro,
        used5h: 1, ceiling5h: 100, resetTime5h: Date(),
        usedWeek: 1, ceilingWeek: 1000, resetTimeWeek: Date(),
        sourceVersion: "fake", raw: Data())
    let c = UsageController(scraper: FakeScraper(snap: snap),
                            snapshots: SnapshotRepository(dbq: dbq, deviceID: "d1"),
                            forecaster: LinearForecaster())
    try await c.pollOnce()
    let arr = try c.snapshots(within: 60 * 60)
    XCTAssertEqual(arr.count, 1)
}
```

- [ ] **Step 2: Implement** in `UsageController`:

```swift
public func snapshots(within seconds: TimeInterval) throws -> [UsageSnapshot] {
    try snapshots.fetchRecent(within: seconds)
}
```

- [ ] **Step 3:** Update `refreshSnapshots()` in `PopoverRootView` to call `controller.snapshots(within: timeframe.seconds)`.
- [ ] **Step 4:** Run; verify chart shows actual history accumulating.
- [ ] **Step 5:** Commit `git commit -am "feat(mac): chart pulls real history from controller"`

---

# Phase 13 — macOS settings window

### Task 40: `SettingsWindow` with Tabs (Account, Alerts, Data)

**Files:**
- Create: `Apps/ClaudeUsageMac/Settings/SettingsWindow.swift`
- Create: `Apps/ClaudeUsageMac/Settings/AccountPane.swift`
- Create: `Apps/ClaudeUsageMac/Settings/AlertsPane.swift`
- Create: `Apps/ClaudeUsageMac/Settings/DataPane.swift`

- [ ] **Step 1:** `SettingsWindow.swift`:

```swift
import AppKit
import SwiftUI
import UsageCore

@MainActor
final class SettingsWindowController {
    private static var window: NSWindow?

    static func show(ctx: AppContext) {
        if let w = window { w.makeKeyAndOrderFront(nil); return }
        let view = TabView {
            AccountPane(ctx: ctx).tabItem { Label("Account", systemImage: "person") }
            AlertsPane(ctx: ctx).tabItem { Label("Alerts", systemImage: "bell") }
            DataPane(ctx: ctx).tabItem { Label("Data", systemImage: "tray") }
        }.frame(width: 420, height: 320).padding(12)
        let host = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: host)
        w.title = "Claude Usage Settings"
        w.styleMask = [.titled, .closable]
        w.makeKeyAndOrderFront(nil)
        window = w
    }
}
```

- [ ] **Step 2:** `AccountPane.swift`:

```swift
import SwiftUI
import UsageCore

struct AccountPane: View {
    let ctx: AppContext
    @State private var email: String = "—"
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Signed in as \(email)")
            Button("Sign out") {
                try? ctx.cookieStore.clear()
                NSApp.terminate(nil)        // simplest: reset on relaunch
            }
            Button("Re-login") {
                LoginWindowController.show(ctx: ctx, onComplete: {})
            }
        }
        .padding()
        .onAppear {
            // could decode JWT / hit /me — leave as "—" until endpoint discovery
        }
    }
}
```

- [ ] **Step 3:** `AlertsPane.swift`:

```swift
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
        }
        .padding()
        .onAppear {
            let raw = (try? ctx.settings.get(.alertThresholds)) ?? AlertKind.allCases.map(\.rawValue).joined(separator: ",")
            enabled = Set(raw.split(separator: ",").map(String.init))
        }
    }
    private func label(_ k: AlertKind) -> String {
        switch k {
        case .fiveHourForecast: return "Warn before hitting 5h limit"
        case .fiveHourHit: return "Notify when 5h limit reached"
        case .weekNinety: return "Notify at 90% of weekly limit"
        case .weekHundred: return "Notify when weekly limit reached"
        case .authExpired: return "Notify when login expires"
        case .scrapeBroken: return "Notify when source format changes"
        }
    }
}
```

- [ ] **Step 4:** `DataPane.swift`:

```swift
import SwiftUI
import UsageCore

struct DataPane: View {
    let ctx: AppContext
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Export history (CSV)") { exportCSV() }
            Button("Delete all local + iCloud data", role: .destructive) {
                let alert = NSAlert()
                alert.messageText = "Delete all data?"
                alert.alertStyle = .critical
                alert.addButton(withTitle: "Delete")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn {
                    try? FileManager.default.removeItem(at: dbURL())
                    NSApp.terminate(nil)
                }
            }
        }.padding()
    }
    private func dbURL() -> URL {
        let dir = try! FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent("ClaudeUsage")
        return dir.appendingPathComponent("usage.db")
    }
    private func exportCSV() {
        // Write simple CSV from snapshots. Save panel.
        let panel = NSSavePanel(); panel.nameFieldStringValue = "claude-usage.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var csv = "timestamp,used_5h,ceiling_5h,used_week,ceiling_week,plan\n"
        if let arr = try? ctx.snapshots.fetchRecent(within: 30*86400) {
            for s in arr {
                csv += "\(Int(s.timestamp.timeIntervalSince1970)),\(s.used5h),\(s.ceiling5h),\(s.usedWeek),\(s.ceilingWeek),\(s.plan.displayName)\n"
            }
        }
        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }
}
```

- [ ] **Step 5:** Add a right-click menu to `StatusItemController`:

```swift
init() {
    if let button = item.button {
        button.title = "⌬ ⏳"
        button.target = self
        button.action = #selector(buttonClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }
    let menu = NSMenu()
    menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
    menu.addItem(.separator())
    menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
    self.menu = menu
}
@objc private func openSettings() { /* delegate-via-AppDelegate */ }
@objc private func quit() { NSApp.terminate(nil) }
```

The cleanest pattern is to assign menu only on right-click via `NSEvent`, and otherwise fire `onClick`. For brevity here, use `NSStatusItem.menu = menu` and intercept left-click via custom action. Engineer can refine.

- [ ] **Step 6:** Commit `git commit -am "feat(mac): settings window with Account/Alerts/Data panes"`

---

# Phase 14 — Dispatch alerts on Mac

### Task 41: Wire `AlertEngine` + `NotificationDispatcher` into the polling loop

**Files:**
- Modify: `Sources/UsageCore/Polling/UsageController.swift`
- Modify: `Apps/ClaudeUsageMac/AppContext.swift` (or `AppDelegate`)

- [ ] **Step 1: Failing test** — controller invokes a `AlertSink` for fired alerts:

```swift
func test_alerts_fire_through_sink() async throws {
    let dbq = try DatabaseQueue(); try Database.migrator.migrate(dbq)
    let now = Date()
    // snapshot at 95% to fire the 5h-hit if threshold set so
    let snap = UsageSnapshot(timestamp: now, plan: .pro,
        used5h: 100, ceiling5h: 100, resetTime5h: now.addingTimeInterval(60),
        usedWeek: 0, ceilingWeek: 1000, resetTimeWeek: now,
        sourceVersion: "fake", raw: Data())
    let sink = SpySink()
    let c = UsageController(scraper: FakeScraper(snap: snap),
                            snapshots: SnapshotRepository(dbq: dbq, deviceID: "d1"),
                            forecaster: LinearForecaster(),
                            alertEngine: AlertEngine(),
                            alertState: AlertStateRepository(dbq: dbq),
                            alertSink: sink)
    try await c.pollOnce()
    XCTAssertTrue(sink.fired.contains(.fiveHourHit))
}
final class SpySink: AlertSink {
    var fired: Set<AlertKind> = []
    func deliver(_ k: AlertKind, snapshot: UsageSnapshot, forecast: ForecastResult?) async {
        fired.insert(k)
    }
}
```

- [ ] **Step 2: Run** → fail.
- [ ] **Step 3: Implement** — extend controller:

```swift
public protocol AlertSink {
    func deliver(_ kind: AlertKind, snapshot: UsageSnapshot, forecast: ForecastResult?) async
}

extension UsageController {
    // additional ctor-injected deps
}

// In UsageController:
private let alertEngine: AlertEngine?
private let alertState: AlertStateRepository?
private let alertSink: AlertSink?

public init(scraper: UsageScraper,
            snapshots: SnapshotRepository,
            forecaster: LinearForecaster,
            sync: CloudKitSyncing? = nil,
            syncIntervalSeconds: TimeInterval = 300,
            alertEngine: AlertEngine? = nil,
            alertState: AlertStateRepository? = nil,
            alertSink: AlertSink? = nil) {
    self.scraper = scraper; self.snapshots = snapshots
    self.forecaster = forecaster; self.sync = sync
    self.syncIntervalSeconds = syncIntervalSeconds
    self.alertEngine = alertEngine
    self.alertState = alertState
    self.alertSink = alertSink
}

// pollOnce(): after computing forecast (i.e. after `state.forecast = …` is set):
if let engine = alertEngine, let stateRepo = alertState, let sink = alertSink {
    let kinds = engine.decide(
        snapshot: snap,
        forecast: state.forecast,
        alertState: AlertStateAdapter(repo: stateRepo),
        settings: .default,
        now: Date())
    for k in kinds {
        try? stateRepo.recordFire(k, at: Date())
        await sink.deliver(k, snapshot: snap, forecast: state.forecast)
    }
}
```

(adapter shown below)

```swift
struct AlertStateAdapter: AlertStateReader {
    let repo: AlertStateRepository
    func lastFired(_ kind: AlertKind) -> Date? { try? repo.lastFired(kind) }
    func snoozedUntil(_ kind: AlertKind) -> Date? { try? repo.snoozedUntil(kind) }
}
```

- [ ] **Step 4: Run** → pass.
- [ ] **Step 5: Wire `NotificationDispatcher` into `AppContext`:**

```swift
// AppContext / AppDelegate.startPolling:
let dispatcher = NotificationDispatcher()
Task { _ = await dispatcher.requestAuthorization() }
ctx.controller = UsageController(
    scraper: factory.current(),
    snapshots: ctx.snapshots,
    forecaster: LinearForecaster(),
    sync: nil,
    alertEngine: AlertEngine(),
    alertState: ctx.alertState,
    alertSink: NotificationSinkAdapter(dispatcher: dispatcher))
```

```swift
struct NotificationSinkAdapter: AlertSink {
    let dispatcher: NotificationDispatcher
    func deliver(_ k: AlertKind, snapshot s: UsageSnapshot, forecast f: ForecastResult?) async {
        await dispatcher.deliver(k, snapshot: s, forecast: f)
    }
}
```

- [ ] **Step 6: Commit** `git commit -am "feat(mac): wire AlertEngine to UNUserNotificationCenter"`

---

# Phase 15 — iOS app shell

### Task 42: Add iOS app target + App Group

**Files:**
- Create: `Apps/ClaudeUsageiOS/ClaudeUsageiOSApp.swift`
- Create: `Apps/ClaudeUsageiOS/Info.plist`

- [ ] **Step 1:** In Xcode, **File → New → Target → iOS App**, name `ClaudeUsageiOS`, SwiftUI App lifecycle. Add `UsageCore` package as a dependency.
- [ ] **Step 2: Create App Group** for sharing SQLite with widget extension. Identifier: `group.com.claudeusage.shared`. Enable on iOS app target capabilities.
- [ ] **Step 3: Replace generated app file:**

```swift
import SwiftUI
import UsageCore

@main
struct ClaudeUsageiOSApp: App {
    @StateObject var bootstrap = AppBootstrap()
    var body: some Scene {
        WindowGroup {
            if bootstrap.needsLogin {
                LoginSheet(bootstrap: bootstrap)
            } else {
                MainScreenView().environmentObject(bootstrap)
            }
        }
    }
}
```

- [ ] **Step 4:** Create `AppBootstrap.swift` (iOS counterpart to AppContext):

```swift
import Foundation
import GRDB
import UsageCore
import SwiftUI
import WidgetKit

@MainActor
final class AppBootstrap: ObservableObject {
    @Published var needsLogin: Bool = true
    let dbq: DatabaseQueue
    let deviceID: String
    let keychain = KeychainStore()
    let snapshots: SnapshotRepository
    let alertState: AlertStateRepository
    let settings: SettingsRepository
    let cookieStore: CookiePackageStore
    var controller: UsageController?
    var pollingTimer: PollingTimer?

    init() {
        let groupID = "group.com.claudeusage.shared"
        let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)!
        self.dbq = try! Database.openOnDisk(at: dir.appendingPathComponent("usage.db"))
        self.deviceID = (try? DeviceID.getOrCreate(in: keychain)) ?? UUID().uuidString
        self.snapshots = SnapshotRepository(dbq: dbq, deviceID: deviceID)
        self.alertState = AlertStateRepository(dbq: dbq)
        self.settings = SettingsRepository(dbq: dbq)
        self.cookieStore = CookiePackageStore(keychain: keychain, deviceID: deviceID)
        self.needsLogin = (try? cookieStore.load()) == nil
    }

    func startPolling() {
        guard let pkg = try? cookieStore.load() else { return }
        let endpoint = EndpointConfig(jsonEndpoint: nil)  // load from settings if persisted
        let factory = ScraperFactory(config: endpoint, cookies: pkg)
        let dispatcher = NotificationDispatcher()
        Task { _ = await dispatcher.requestAuthorization() }
        let c = UsageController(
            scraper: factory.current(), snapshots: snapshots,
            forecaster: LinearForecaster(), sync: nil,
            alertEngine: AlertEngine(), alertState: alertState,
            alertSink: NotificationSinkAdapter(dispatcher: dispatcher))
        controller = c
        let timer = PollingTimer(interval: 90, jitter: 10)
        timer.onTick = { [weak self] in Task { @MainActor in await self?.tick() } }
        timer.start()
        pollingTimer = timer
        Task { await tick() }
    }

    private func tick() async {
        guard let c = controller else { return }
        try? await c.pollOnce()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
```

- [ ] **Step 5:** Build iOS scheme, run on simulator. Expected: white screen, login sheet to be implemented in Task 43.
- [ ] **Step 6:** Commit `git commit -am "feat(ios): bootstrap iOS app with App Group SQLite"`

### Task 43: `LoginSheet` (iOS)

**Files:**
- Create: `Apps/ClaudeUsageiOS/Auth/LoginSheet.swift`

- [ ] **Step 1:** Implement:

```swift
import SwiftUI
import WebKit
import UsageCore

struct LoginSheet: View {
    @ObservedObject var bootstrap: AppBootstrap

    var body: some View {
        WebViewLogin { pkg in
            try? bootstrap.cookieStore.save(pkg)
            bootstrap.needsLogin = false
            bootstrap.startPolling()
        }
    }
}

struct WebViewLogin: UIViewRepresentable {
    let onSuccess: (CookiePackage) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        let v = WKWebView(frame: .zero, configuration: cfg)
        let coord = context.coordinator
        v.navigationDelegate = coord
        coord.onSuccess = onSuccess
        v.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        return v
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, WKNavigationDelegate {
        var onSuccess: ((CookiePackage) -> Void)?
        private var fired = false
        func webView(_ wv: WKWebView, didFinish nav: WKNavigation!) {
            guard let url = wv.url, !url.path.contains("/login"), url.host?.contains("claude.ai") == true,
                  !fired else { return }
            fired = true
            Task {
                let cookies = await wv.configuration.websiteDataStore.httpCookieStore.allCookies()
                wv.evaluateJavaScript("navigator.userAgent") { v, _ in
                    let ua = (v as? String) ?? "Mozilla/5.0"
                    self.onSuccess?(CookieReader.package(from: cookies, userAgent: ua))
                }
            }
        }
    }
}
```

- [ ] **Step 2:** Build, run on device (Simulator's WKWebView may not handle Cloudflare reliably). Sign in → polling begins.
- [ ] **Step 3:** Commit `git commit -am "feat(ios): WKWebView login sheet"`

### Task 44: `MainScreenView` (iOS)

**Files:**
- Create: `Apps/ClaudeUsageiOS/Main/MainScreenView.swift`
- Create: `Apps/ClaudeUsageiOS/Main/RecentActivitySection.swift`
- Create: `Apps/ClaudeUsageiOS/Main/DevicesSection.swift`

- [ ] **Step 1:** `MainScreenView`:

```swift
import SwiftUI
import UsageCore

struct MainScreenView: View {
    @EnvironmentObject var bootstrap: AppBootstrap
    @State private var timeframe: Timeframe = .oneHour
    @State private var showSettings = false
    @State private var snapshots: [UsageSnapshot] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        GaugeCardView(label: "5h",
                            percent: bootstrap.controller?.state.latest?.fraction5h ?? 0,
                            resetCaption: "—")
                        GaugeCardView(label: "Week",
                            percent: bootstrap.controller?.state.latest?.fractionWeek ?? 0,
                            resetCaption: "—")
                    }
                    TimeframePicker(selection: $timeframe)
                    ChartView(snapshots: snapshots, forecast: bootstrap.controller?.state.forecast,
                              timeframe: timeframe)
                        .frame(height: 120)
                    if timeframe == .oneHour || timeframe == .eightHour {
                        ForecastCaptionView(forecast: bootstrap.controller?.state.forecast)
                    }
                    RecentActivitySection(snapshot: bootstrap.controller?.state.latest)
                    DevicesSection()
                }.padding()
            }
            .refreshable {
                try? await bootstrap.controller?.pollOnce()
                refreshSnapshots()
            }
            .navigationTitle("Claude Usage")
            .toolbar {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
            .sheet(isPresented: $showSettings) { SettingsSheet() }
            .onAppear(perform: refreshSnapshots)
            .onChange(of: timeframe) { refreshSnapshots() }
            .onChange(of: bootstrap.controller?.state.lastPollAt) { refreshSnapshots() }
        }
    }

    private func refreshSnapshots() {
        snapshots = (try? bootstrap.controller?.snapshots(within: timeframe.seconds)) ?? []
    }
}
```

(`GaugeCardView`, `ChartView`, `TimeframePicker`, `ForecastCaptionView` need to be moved to the package or duplicated in iOS; the cleanest approach is to **move them to `UsageCore`** as cross-platform SwiftUI views, conditional on `#if canImport(AppKit)`. Add a refactor task.)

- [ ] **Step 2: Refactor task:** Move `GaugeCardView`, `ChartView`, `TimeframePicker`, `ForecastCaptionView`, `FooterView` from `Apps/ClaudeUsageMac/` into `Sources/UsageCore/UI/`. Replace `NSColor` with cross-platform `Color`. Update macOS imports.
- [ ] **Step 3:** Build iOS scheme. Expected: main screen renders with gauges + chart.
- [ ] **Step 4:** Commit `git commit -am "feat(ios): main screen + cross-platform SwiftUI components"`

### Task 45: `RecentActivitySection` and `DevicesSection`

**Files:**
- Create: `Apps/ClaudeUsageiOS/Main/RecentActivitySection.swift`
- Create: `Apps/ClaudeUsageiOS/Main/DevicesSection.swift`

- [ ] **Step 1:**

```swift
import SwiftUI
import UsageCore

struct RecentActivitySection: View {
    let snapshot: UsageSnapshot?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent activity").font(.headline)
            Text("Today's tokens: \(snapshot?.used5h ?? 0)")
            // peak hour calculation deferred — placeholder reads from snapshots history
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DevicesSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Devices syncing").font(.headline)
            Text("• iPhone (just now)")
            Text("• Mac (—)")        // populated when CloudKit sync ships
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

- [ ] **Step 2:** Commit `git commit -am "feat(ios): recent activity + devices sections (skeletons)"`

### Task 46: `SettingsSheet` (iOS) and `OnboardingOverlay`

**Files:**
- Create: `Apps/ClaudeUsageiOS/Settings/SettingsSheet.swift`
- Create: `Apps/ClaudeUsageiOS/Onboarding/OnboardingOverlay.swift`

- [ ] **Step 1:** `SettingsSheet`:

```swift
import SwiftUI
import UsageCore

struct SettingsSheet: View {
    @EnvironmentObject var bootstrap: AppBootstrap
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    Button("Sign out") {
                        try? bootstrap.cookieStore.clear()
                        bootstrap.needsLogin = true
                        dismiss()
                    }
                }
                Section("Alerts") {
                    ForEach(AlertKind.allCases, id: \.self) { k in
                        Toggle(label(k), isOn: .constant(k.defaultEnabled))
                    }
                }
                Section("Data") {
                    Button("Export history (CSV)", action: exportCSV)
                    Button("Delete all data", role: .destructive, action: { /* ... */ })
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private func label(_ k: AlertKind) -> String {
        switch k {
        case .fiveHourForecast: return "Warn before hitting 5h limit"
        case .fiveHourHit: return "Notify when 5h limit reached"
        case .weekNinety: return "Notify at 90% of weekly"
        case .weekHundred: return "Notify when weekly limit reached"
        case .authExpired: return "Notify when login expires"
        case .scrapeBroken: return "Notify when source format changes"
        }
    }

    private func exportCSV() { /* same as Mac DataPane */ }
}
```

- [ ] **Step 2:** `OnboardingOverlay`:

```swift
import SwiftUI

struct OnboardingOverlay: View {
    @State private var step = 0
    let onDone: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            switch step {
            case 0:
                Text("Welcome to Claude Usage").font(.title)
                Text("These are your gauges — they show how much of your 5-hour and weekly windows are used.")
            case 1:
                Text("Charts and forecast").font(.title)
                Text("Tap timeframes to see history. The dashed line projects when you'll hit the limit.")
            default:
                Text("Add a widget").font(.title)
                Text("Long-press your home screen to add the Claude Usage widget for at-a-glance checks.")
            }
            Button(step < 2 ? "Next" : "Done") { step < 2 ? step += 1 : onDone() }
        }.padding(32)
    }
}
```

Wire `OnboardingOverlay` to display once after first poll (track via `SettingsRepository.set(.onboarded, "1")`).

- [ ] **Step 3:** Commit `git commit -am "feat(ios): settings sheet + onboarding overlay"`

---

# Phase 16 — iOS widgets

### Task 47: Add Widget extension target

**Files:**
- Create: `Apps/ClaudeUsageWidgets/WidgetBundle.swift`
- Create: `Apps/ClaudeUsageWidgets/Provider/TimelineProvider.swift`
- Create: `Apps/ClaudeUsageWidgets/Provider/SnapshotEntry.swift`

- [ ] **Step 1:** Xcode → New Target → Widget Extension. Name `ClaudeUsageWidgets`. Enable Widget Bundle. Add App Group `group.com.claudeusage.shared` to its capabilities. Link `UsageCore` package.
- [ ] **Step 2:** `SnapshotEntry`:

```swift
import WidgetKit
import UsageCore

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
}
```

- [ ] **Step 3:** `TimelineProvider`:

```swift
import WidgetKit
import GRDB
import UsageCore

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        .init(date: Date(), snapshot: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(.init(date: Date(), snapshot: latest()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: Date(), snapshot: latest())
        let next = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func latest() -> UsageSnapshot? {
        let groupID = "group.com.claudeusage.shared"
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID),
              let dbq = try? Database.openOnDisk(at: dir.appendingPathComponent("usage.db")) else { return nil }
        // any device id works for read
        let repo = SnapshotRepository(dbq: dbq, deviceID: "widget-read")
        return try? repo.mostRecent()
    }
}
```

- [ ] **Step 4:** `WidgetBundle.swift`:

```swift
import WidgetKit
import SwiftUI

@main
struct ClaudeUsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        SmallWidget()
        MediumWidget()
        LargeWidget()
        LockCircularWidget()
        LockRectangularWidget()
    }
}
```

- [ ] **Step 5:** Commit `git commit -am "feat(widgets): bundle + provider scaffold"`

### Task 48: `SmallWidget`

**Files:**
- Create: `Apps/ClaudeUsageWidgets/Home/SmallWidget.swift`

- [ ] **Step 1:**

```swift
import WidgetKit
import SwiftUI
import UsageCore

struct SmallWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "claudeusage.small", provider: UsageProvider()) { entry in
            SmallWidgetView(entry: entry)
        }
        .supportedFamilies([.systemSmall])
        .configurationDisplayName("Claude · 5h")
        .description("Current 5-hour window usage")
    }
}

struct SmallWidgetView: View {
    let entry: SnapshotEntry
    var body: some View {
        let pct = entry.snapshot?.fraction5h ?? 0
        VStack(alignment: .leading, spacing: 6) {
            Text("CLAUDE · 5H").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            Spacer()
            Text("\(Int(pct * 100))%").font(.system(size: 32, weight: .semibold, design: .rounded))
            ProgressView(value: pct).tint(color(pct))
            Text(reset(entry.snapshot?.resetTime5h)).font(.system(size: 9)).foregroundStyle(.secondary)
        }.padding()
    }
    private func color(_ p: Double) -> Color { p >= 0.9 ? .red : (p >= 0.75 ? .orange : .green) }
    private func reset(_ d: Date?) -> String {
        guard let d, d > Date() else { return "—" }
        let s = Int(d.timeIntervalSinceNow)
        return "\(s/3600)h \(s%3600/60)m left"
    }
}
```

- [ ] **Step 2:** Commit `git commit -am "feat(widgets): SmallWidget"`

### Task 49: `MediumWidget`

**Files:**
- Create: `Apps/ClaudeUsageWidgets/Home/MediumWidget.swift`

```swift
import WidgetKit
import SwiftUI
import UsageCore

struct MediumWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "claudeusage.medium", provider: UsageProvider()) { entry in
            MediumWidgetView(entry: entry)
        }.supportedFamilies([.systemMedium])
    }
}

struct MediumWidgetView: View {
    let entry: SnapshotEntry
    var body: some View {
        HStack(spacing: 12) {
            mini("5H", entry.snapshot?.fraction5h ?? 0)
            mini("WEEK", entry.snapshot?.fractionWeek ?? 0)
            Spacer()
            // sparkline placeholder; use Charts when reading history is wired
        }.padding()
    }
    @ViewBuilder
    private func mini(_ label: String, _ p: Double) -> some View {
        VStack(alignment: .leading) {
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
            Text("\(Int(p * 100))%").font(.system(size: 22, weight: .semibold, design: .rounded))
            ProgressView(value: p).tint(p >= 0.9 ? .red : (p >= 0.75 ? .orange : .green))
        }.frame(width: 80, alignment: .leading)
    }
}
```

- [ ] **Commit** `git commit -am "feat(widgets): MediumWidget"`

### Task 50: `LargeWidget` with chart

**Files:**
- Create: `Apps/ClaudeUsageWidgets/Home/LargeWidget.swift`
- Modify: `TimelineProvider` to also load a recent-history slice

- [ ] **Step 1:** Provide a richer entry:

```swift
struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
    let history: [UsageSnapshot]
}
```

Update `latest()` to also `fetchRecent(within: 8 * 3600)`.

- [ ] **Step 2:** `LargeWidget`:

```swift
import WidgetKit
import SwiftUI
import Charts
import UsageCore

struct LargeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "claudeusage.large", provider: UsageProvider()) { entry in
            LargeWidgetView(entry: entry)
        }.supportedFamilies([.systemLarge])
    }
}

struct LargeWidgetView: View {
    let entry: SnapshotEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CLAUDE USAGE").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                mini("5H", entry.snapshot?.fraction5h ?? 0)
                mini("WEEK", entry.snapshot?.fractionWeek ?? 0)
            }
            Text("Last 8h").font(.system(size: 9)).foregroundStyle(.secondary)
            Chart {
                ForEach(entry.history, id: \.timestamp) { s in
                    LineMark(x: .value("t", s.timestamp), y: .value("p", s.fraction5h * 100))
                        .foregroundStyle(.green)
                }
            }
            .frame(height: 80)
            .chartYScale(domain: 0...100)
            Spacer()
            Text("Updated \(format(entry.date))").font(.system(size: 9)).foregroundStyle(.tertiary)
        }.padding()
    }
    @ViewBuilder
    private func mini(_ label: String, _ p: Double) -> some View {
        VStack(alignment: .leading) {
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
            Text("\(Int(p * 100))%").font(.system(size: 22, weight: .semibold))
            ProgressView(value: p)
        }.frame(width: 100, alignment: .leading)
    }
    private func format(_ d: Date) -> String {
        let s = Int(Date().timeIntervalSince(d))
        return s < 60 ? "\(s)s ago" : "\(s/60)m ago"
    }
}
```

- [ ] **Step 3:** Commit `git commit -am "feat(widgets): LargeWidget with sparkline"`

### Task 51: Lock-screen widgets

**Files:**
- Create: `Apps/ClaudeUsageWidgets/Lock/LockCircularWidget.swift`
- Create: `Apps/ClaudeUsageWidgets/Lock/LockRectangularWidget.swift`

```swift
// LockCircularWidget.swift
import WidgetKit
import SwiftUI
import UsageCore

struct LockCircularWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "claudeusage.lock.circular", provider: UsageProvider()) { entry in
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: entry.snapshot?.fraction5h ?? 0)
                    .rotation(.degrees(-90))
                    .stroke(.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                Text("\(Int((entry.snapshot?.fraction5h ?? 0) * 100))")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }.padding(2)
        }.supportedFamilies([.accessoryCircular])
    }
}
```

```swift
// LockRectangularWidget.swift
import WidgetKit
import SwiftUI
import UsageCore

struct LockRectangularWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "claudeusage.lock.rect", provider: UsageProvider()) { entry in
            VStack(alignment: .leading, spacing: 2) {
                Text("Claude · 5h").font(.system(size: 11, weight: .semibold))
                Text("\(Int((entry.snapshot?.fraction5h ?? 0) * 100))% · \(reset(entry.snapshot?.resetTime5h)) left")
                    .font(.system(size: 11))
            }
        }.supportedFamilies([.accessoryRectangular])
    }
    private static func reset(_ d: Date?) -> String {
        guard let d, d > Date() else { return "—" }
        let s = Int(d.timeIntervalSinceNow); return "\(s/3600)h \(s%3600/60)m"
    }
    private func reset(_ d: Date?) -> String { Self.reset(d) }
}
```

- [ ] **Commit** `git commit -am "feat(widgets): lock-screen circular + rectangular"`

---

# Phase 17 — Final integration

### Task 52: Wire CloudKit on macOS + iOS

**Files:**
- Modify: `Apps/ClaudeUsageMac/AppContext.swift` (or `AppDelegate`)
- Modify: `Apps/ClaudeUsageiOS/AppBootstrap.swift`

- [ ] **Step 1:** Set up Apple Developer account + CloudKit container `iCloud.com.claudeusage.shared`. Update both Mac and iOS app entitlements to include this container under "iCloud" → "CloudKit Services."
- [ ] **Step 2:** Wire `CloudKitSync` into both controllers:

```swift
let sync = CloudKitSync(containerIdentifier: "iCloud.com.claudeusage.shared",
                        deviceID: ctx.deviceID)
ctx.controller = UsageController(
    scraper: factory.current(),
    snapshots: ctx.snapshots,
    forecaster: LinearForecaster(),
    sync: sync,
    syncIntervalSeconds: 300,
    alertEngine: AlertEngine(),
    alertState: ctx.alertState,
    alertSink: NotificationSinkAdapter(dispatcher: dispatcher))
```

- [ ] **Step 3:** Add a fetch-on-launch to merge remote snapshots:

```swift
// In startPolling() before tick():
Task {
    let lastTs = (try? Double(ctx.settings.get(.lastCloudSyncTs) ?? "0")) ?? 0
    let since = Date(timeIntervalSince1970: lastTs)
    if let remote = try? await sync.fetchSince(since) {
        for s in remote { try? ctx.snapshots.insert(s) }
        try? ctx.settings.set(.lastCloudSyncTs, String(Date().timeIntervalSince1970))
    }
}
```

- [ ] **Step 4:** Manual verify: run macOS for 10 min → quit. Run iOS app → expect macOS-side snapshots to populate iOS chart within 1-2 min.
- [ ] **Step 5:** Commit `git commit -am "feat: wire CloudKit sync on both platforms"`

### Task 53: `RetentionJob` scheduling

**Files:**
- Modify: `AppContext` (Mac) and `AppBootstrap` (iOS)

- [ ] **Step 1:** Mac: schedule the retention job hourly via `Timer.scheduledTimer(withTimeInterval: 3600, repeats: true)`.

```swift
Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
    try? RetentionJob(dbq: ctx.dbq).run()
}
RetentionJob(dbq: ctx.dbq).run()  // also run once on launch
```

- [ ] **Step 2:** iOS: same approach, but also run on every `applicationDidEnterForeground` to handle long sleeps.
- [ ] **Step 3:** Commit `git commit -am "feat: schedule hourly RetentionJob"`

### Task 54: Manual verification suite (success criteria from spec § 9.4)

**Files:**
- Create: `docs/manual-verification.md`

- [ ] **Step 1:** Document the seven success criteria as a checklist with reproducible steps:

```markdown
# Manual verification checklist

- [ ] Mac menu bar shows current 5h % within 90s of usage change
  - Steps: send a long Claude prompt, watch menu bar within 2 min.
- [ ] iPhone widget shows the same data within 5 min of an iPhone-side poll
  - Steps: foreground iOS app, leave 5 min, lock device, observe lock-screen widget.
- [ ] Charts render in <100ms from local cache (popover open time)
  - Steps: with full 24h history, click menu bar — popover appears instantly.
- [ ] Forecast caption appears with R² ≥ 0.5 and is hidden otherwise
  - Steps: bursty usage, idle usage; observe caption presence.
- [ ] Auth flow recoverable in <30s when session expires
  - Steps: clear sessionKey via Keychain Access; observe banner → re-login.
- [ ] Zero crashes in 24h soak test on each platform
  - Steps: leave running 24h, check `Console.app` for crash logs.
- [ ] Poll failure rate <1% (excluding Anthropic outages)
  - Steps: tail SQLite for source-version mismatches; sample by hour.
```

- [ ] **Step 2:** Commit `git commit -am "docs: manual verification checklist for v1 success criteria"`

### Task 55: README

**Files:**
- Create: `README.md`

- [ ] **Step 1:**

```markdown
# Claude Usage

Native macOS menu bar app + iOS companion that monitors Claude.ai / Claude Code usage limits.

## Build

1. Open `ClaudeUsage.xcworkspace` in Xcode 15+.
2. Set up an Apple Developer team and configure signing for the macOS, iOS, and Widget targets.
3. In **Signing & Capabilities** for each target, add the iCloud container `iCloud.com.claudeusage.shared`.
4. Add the App Group `group.com.claudeusage.shared` to the iOS app and Widget extension targets.
5. Run the macOS scheme.
6. Run the iOS scheme on a device (Simulator may not handle Cloudflare reliably).

## First run

You'll be prompted to log in to claude.ai. After login, the app polls every 90 seconds and shows your 5h-window and weekly usage. See `docs/superpowers/specs/2026-04-30-claude-usage-tracker-design.md` for full design.

## Endpoint discovery

The actual JSON endpoint is discovered manually on first run — see Task 32 in the implementation plan.
```

- [ ] **Step 2:** Commit `git commit -am "docs: README with build instructions"`

---

# Self-review notes

**Spec coverage check:**
- § 1 system overview → covered by Tasks 6-10, 22, 28-30
- § 2 auth → Tasks 11-14, 31, 33
- § 3 scraper → Tasks 15-18, 32 (endpoint discovery)
- § 4 storage → Tasks 6-10
- § 5 forecast → Tasks 19-20
- § 6 macOS UI → Tasks 28-30, 34-40
- § 7 iOS UI → Tasks 42-46
- § 8 notifications → Tasks 23-24, 41
- § 9 risks → addressed via tests (schema drift, auth recovery, retention) and § 9.4 success criteria → Task 54
- Decision log items 1-12 → all reflected in tasks

**Placeholder scan:** the only forward-looking item is the JSON endpoint discovery (Task 32), which is intentionally a manual step blocking further automated work.

**Type consistency:** `UsageSnapshot`, `ForecastResult`, `Plan`, `AlertKind`, `ScrapeError` defined once in Phase 2 and referenced consistently. `KeychainStoring` protocol defined in Task 11 and reused in Tasks 12-14. `AlertSink` and `CloudKitSyncing` protocols introduced where dependency injection is needed for testing.

**Open dependencies on external systems:** Apple Developer account (CloudKit), real iCloud account on test device, claude.ai login credentials.
