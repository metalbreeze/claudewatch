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
        case endpointConfig           // discovered claude.ai usage URL (Task 32)
        case menuBarShow5h            // "1"|"0" — see getBool/setBool
        case menuBarShowWeek          // "1"|"0"
        case menuBarShowFable         // "1"|"0"
        case menuBarShowLabels        // "1"|"0"
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
}
