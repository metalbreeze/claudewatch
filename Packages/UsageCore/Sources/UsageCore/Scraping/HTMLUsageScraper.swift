import Foundation

public struct HTMLUsageScraper: UsageScraper {
    public let sourceVersion = "html-v1"
    public init() {}
    public func fetchSnapshot() async throws -> UsageSnapshot {
        throw ScrapeError.unknown("HTMLUsageScraper not implemented yet — discover endpoint first")
    }
}
