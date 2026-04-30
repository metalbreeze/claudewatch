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
    private let snapshotRepo: SnapshotRepository
    private let forecaster: LinearForecaster
    private let sync: CloudKitSyncing?
    private let syncIntervalSeconds: TimeInterval
    private var lastSyncedAt: Date?
    private var pendingForSync: [UsageSnapshot] = []
    private let alertEngine: AlertEngine?
    private let alertState: AlertStateRepository?
    private let alertSink: AlertSink?

    public init(scraper: UsageScraper,
                snapshots: SnapshotRepository,
                forecaster: LinearForecaster,
                sync: CloudKitSyncing? = nil,
                syncIntervalSeconds: TimeInterval = 300,
                alertEngine: AlertEngine? = nil,
                alertState: AlertStateRepository? = nil,
                alertSink: AlertSink? = nil) {
        self.scraper = scraper
        self.snapshotRepo = snapshots          // renamed property
        self.forecaster = forecaster
        self.sync = sync
        self.syncIntervalSeconds = syncIntervalSeconds
        self.alertEngine = alertEngine
        self.alertState = alertState
        self.alertSink = alertSink
    }

    public func pollOnce() async throws {
        do {
            let snap = try await scraper.fetchSnapshot()
            try snapshotRepo.insert(snap)
            state.latest = snap
            state.lastPollAt = Date()
            state.lastError = nil
            state.consecutiveAuthFailures = 0
            let recent = try snapshotRepo.fetchRecent(within: 3600)
            state.forecast = forecaster.forecast(snapshots: recent)
            pendingForSync.append(snap)
            await maybeSync()
            if let engine = alertEngine, let stateRepo = alertState, let sink = alertSink {
                let kinds = engine.decide(
                    snapshot: snap,
                    forecast: state.forecast,
                    alertState: AlertStateAdapter(repo: stateRepo),
                    settings: .default,
                    now: Date())
                for k in kinds {
                    try? stateRepo.recordFire(k, at: Date())
                    await sink.deliver(k, snapshot: snap, forecast: state.forecast)
                }
            }
        } catch let e as ScrapeError {
            state.lastError = e
            if e.isAuthRelated { state.consecutiveAuthFailures += 1 }
            throw e
        }
    }

    public func snapshots(within seconds: TimeInterval) throws -> [UsageSnapshot] {
        try snapshotRepo.fetchRecent(within: seconds)
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
