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

    public init(scraper: UsageScraper, snapshots: SnapshotRepository, forecaster: LinearForecaster) {
        self.scraper = scraper; self.snapshots = snapshots; self.forecaster = forecaster
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
        } catch let e as ScrapeError {
            state.lastError = e
            if e.isAuthRelated { state.consecutiveAuthFailures += 1 }
            throw e
        }
    }
}
