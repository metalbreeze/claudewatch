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

public protocol CloudKitSyncing {
    func uploadPending(snapshots: [UsageSnapshot]) async throws
}

extension CloudKitSync: CloudKitSyncing {
    public func uploadPending(snapshots: [UsageSnapshot]) async throws {
        try await upload(snapshots)
    }
}
