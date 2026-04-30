import Foundation

public protocol AlertSink {
    func deliver(_ kind: AlertKind, snapshot: UsageSnapshot, forecast: ForecastResult?) async
}

/// Adapter that bridges an `AlertStateRepository` (mutable, throws) to the
/// `AlertStateReader` (read-only, non-throwing) interface used by
/// `AlertEngine.decide(...)`.
public struct AlertStateAdapter: AlertStateReader {
    let repo: AlertStateRepository
    public init(repo: AlertStateRepository) { self.repo = repo }
    public func lastFired(_ kind: AlertKind) -> Date? { try? repo.lastFired(kind) }
    public func snoozedUntil(_ kind: AlertKind) -> Date? { try? repo.snoozedUntil(kind) }
}
