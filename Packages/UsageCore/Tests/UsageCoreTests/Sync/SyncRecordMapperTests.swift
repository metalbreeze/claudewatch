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
