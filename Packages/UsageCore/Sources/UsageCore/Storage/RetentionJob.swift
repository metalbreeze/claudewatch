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
