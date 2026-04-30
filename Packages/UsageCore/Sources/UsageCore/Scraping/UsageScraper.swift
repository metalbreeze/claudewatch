import Foundation

public protocol UsageScraper {
    var sourceVersion: String { get }
    func fetchSnapshot() async throws -> UsageSnapshot
}
