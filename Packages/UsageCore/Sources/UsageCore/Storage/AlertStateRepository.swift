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
