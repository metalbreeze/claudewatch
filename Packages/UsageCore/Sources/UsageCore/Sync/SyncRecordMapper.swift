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
