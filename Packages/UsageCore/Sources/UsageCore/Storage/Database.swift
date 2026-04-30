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
