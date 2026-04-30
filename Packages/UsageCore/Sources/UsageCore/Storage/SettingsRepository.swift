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
