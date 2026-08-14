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
}
