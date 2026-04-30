import Foundation

public enum ScrapeError: Error, Equatable {
    case authExpired
    case cloudflareChallenge
    case schemaDrift(version: String, payload: Data)
    case network(URLError)
    case rateLimited(retryAfter: TimeInterval?)
    case unknown(String)

    public var isAuthRelated: Bool {
        if case .authExpired = self { return true }
        return false
    }
    public var requiresWebViewRefresh: Bool {
        if case .cloudflareChallenge = self { return true }
        return false
    }

    public static func == (lhs: ScrapeError, rhs: ScrapeError) -> Bool {
        switch (lhs, rhs) {
        case (.authExpired, .authExpired): return true
        case (.cloudflareChallenge, .cloudflareChallenge): return true
        case let (.schemaDrift(a, _), .schemaDrift(b, _)): return a == b
        case let (.network(a), .network(b)): return a.code == b.code
        case let (.rateLimited(a), .rateLimited(b)): return a == b
        case let (.unknown(a), .unknown(b)): return a == b
        default: return false
        }
    }
}
