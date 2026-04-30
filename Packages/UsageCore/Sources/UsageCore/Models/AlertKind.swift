import Foundation

public enum AlertKind: String, CaseIterable, Codable {
    case fiveHourForecast = "5h-forecast"
    case fiveHourHit = "5h-hit"
    case weekNinety = "week-90"
    case weekHundred = "week-100"
    case authExpired = "auth-expired"
    case scrapeBroken = "scrape-broken"

    public var defaultEnabled: Bool {
        switch self {
        case .scrapeBroken: return true
        default: return true
        }
    }
}
