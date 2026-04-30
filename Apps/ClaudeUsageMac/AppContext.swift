import Foundation
import GRDB
import UsageCore

/// Owns the on-disk and in-memory infrastructure needed by the macOS app:
/// the SQLite database, repositories, Keychain access, and the
/// `UsageController` once polling starts. Constructed on first launch and
/// retained by `AppDelegate` for the lifetime of the process.
@MainActor
final class AppContext {
    let dbq: DatabaseQueue
    let snapshots: SnapshotRepository
    let alertState: AlertStateRepository
    let settings: SettingsRepository
    let keychain: KeychainStore
    let deviceID: String
    let cookieStore: CookiePackageStore
    var controller: UsageController?
    var pollingTimer: PollingTimer?

    init() throws {
        let dir = try FileManager.default
            .url(for: .applicationSupportDirectory,
                 in: .userDomainMask,
                 appropriateFor: nil,
                 create: true)
            .appendingPathComponent("ClaudeUsage", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.dbq = try Database.openOnDisk(at: dir.appendingPathComponent("usage.db"))
        self.keychain = KeychainStore()
        self.deviceID = try DeviceID.getOrCreate(in: keychain)
        self.snapshots = SnapshotRepository(dbq: dbq, deviceID: deviceID)
        self.alertState = AlertStateRepository(dbq: dbq)
        self.settings = SettingsRepository(dbq: dbq)
        self.cookieStore = CookiePackageStore(keychain: keychain, deviceID: deviceID)
    }
}
