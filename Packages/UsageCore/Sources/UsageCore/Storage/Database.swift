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
        // Fable is a per-model weekly quota Anthropic began reporting
        // in 2026-08. Nullable because not every account has one, and
        // because every row written before this migration genuinely
        // has no value — defaulting to 0 would render as "0% used"
        // instead of "no such limit".
        m.registerMigration("v2") { db in
            try db.execute(sql: """
                ALTER TABLE snapshots ADD COLUMN used_fable INTEGER;
                ALTER TABLE snapshots ADD COLUMN reset_fable INTEGER;
                ALTER TABLE snapshots ADD COLUMN fable_is_active INTEGER NOT NULL DEFAULT 0;
            """)
        }
        // Drop snapshots_5min. It was the storage half of a three-tier
        // retention design from the original 2026-04-30 spec: raw 90 s
        // rows for 7 days, 5-minute averages for 7–30 days, nothing
        // beyond. Neither half ever shipped — RetentionJob (the writer)
        // was never called, and SnapshotRepository never grew the
        // read-side branch that was supposed to query this table past
        // the 7-day mark. It has held 0 rows since the day it was
        // created.
        //
        // The design is now actively wrong, not merely unused: the 1-month
        // heatmap added in 2026-08 reads 28 days of RAW snapshots, so the
        // 7-day raw retention this table exists to enable would delete
        // three weeks of the data that feature depends on. Anyone who
        // wires up retention in future must redesign the windows first,
        // and would want Fable columns here too — i.e. they would not
        // reuse this schema. Keeping an empty table shaped by a
        // superseded plan only invites that mistake.
        //
        // v1 is left alone rather than edited. Migrations are immutable
        // history: a fresh install creates the table in v1 and drops it
        // here, which costs microseconds and keeps every recorded
        // migration a truthful account of what the schema did. Rewriting
        // v1 would make the history lie about a database that already
        // exists on disk.
        m.registerMigration("v3") { db in
            try db.execute(sql: "DROP TABLE IF EXISTS snapshots_5min")
        }
        return m
    }

    public static func openOnDisk(at url: URL) throws -> DatabaseQueue {
        let q = try DatabaseQueue(path: url.path)
        try migrator.migrate(q)
        return q
    }
}
