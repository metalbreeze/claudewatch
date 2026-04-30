import Foundation
import GRDB
import UsageCore

/// Owns the on-disk and in-memory infrastructure needed by the macOS app:
/// the SQLite database, repositories, secret store, and the
/// `UsageController` once polling starts. Constructed on first launch and
/// retained by `AppDelegate` for the lifetime of the process.
@MainActor
final class AppContext {
    let dbq: DatabaseQueue
    let snapshots: SnapshotRepository
    let alertState: AlertStateRepository
    let settings: SettingsRepository
    let secrets: KeychainStoring
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
        // FileSecretStore (instead of the system Keychain) avoids the
        // "Claude Usage wants to use your confidential information"
        // prompt that ad-hoc signed dev builds trigger on every rebuild.
        // See FileSecretStore.swift for the threat-model note.
        self.secrets = try FileSecretStore()
        self.deviceID = try DeviceID.getOrCreate(in: secrets)
        self.snapshots = SnapshotRepository(dbq: dbq, deviceID: deviceID)
        self.alertState = AlertStateRepository(dbq: dbq)
        self.settings = SettingsRepository(dbq: dbq)
        self.cookieStore = CookiePackageStore(keychain: secrets, deviceID: deviceID)
    }
}
