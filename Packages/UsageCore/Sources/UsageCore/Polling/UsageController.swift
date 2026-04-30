import Foundation

@MainActor
public final class UsageController: ObservableObject {
    public struct State {
        public var latest: UsageSnapshot?
        public var forecast: ForecastResult?
        public var lastPollAt: Date?
        public var lastError: ScrapeError?
        public var consecutiveAuthFailures: Int = 0
    }

    @Published public private(set) var state = State()

    private let scraper: UsageScraper
    private let snapshots: SnapshotRepository
    private let forecaster: LinearForecaster
    private let sync: CloudKitSyncing?
    private let syncIntervalSeconds: TimeInterval
    private var lastSyncedAt: Date?
    private var pendingForSync: [UsageSnapshot] = []

    public init(scraper: UsageScraper, snapshots: SnapshotRepository,
                forecaster: LinearForecaster,
                sync: CloudKitSyncing? = nil,
                syncIntervalSeconds: TimeInterval = 300) {
        self.scraper = scraper; self.snapshots = snapshots
        self.forecaster = forecaster
        self.sync = sync
        self.syncIntervalSeconds = syncIntervalSeconds
    }

    public func pollOnce() async throws {
        do {
            let snap = try await scraper.fetchSnapshot()
            try snapshots.insert(snap)
            state.latest = snap
            state.lastPollAt = Date()
            state.lastError = nil
            state.consecutiveAuthFailures = 0
            let recent = try snapshots.fetchRecent(within: 3600)
            state.forecast = forecaster.forecast(snapshots: recent)
            pendingForSync.append(snap)
            await maybeSync()
        } catch let e as ScrapeError {
            state.lastError = e
            if e.isAuthRelated { state.consecutiveAuthFailures += 1 }
            throw e
        }
    }

    private func maybeSync() async {
        guard let sync = sync else { return }
        let now = Date()
        if let last = lastSyncedAt, now.timeIntervalSince(last) < syncIntervalSeconds { return }
        let batch = pendingForSync
        pendingForSync.removeAll()
        do { try await sync.uploadPending(snapshots: batch); lastSyncedAt = now }
        catch { pendingForSync = batch + pendingForSync /* retry next time */ }
    }
}
