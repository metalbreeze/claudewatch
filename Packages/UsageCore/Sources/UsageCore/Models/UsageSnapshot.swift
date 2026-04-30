import Foundation

public struct UsageSnapshot: Equatable, Codable {
    public let timestamp: Date
    public let plan: Plan
    public let used5h: Int
    public let ceiling5h: Int
    public let resetTime5h: Date
    public let usedWeek: Int
    public let ceilingWeek: Int
    public let resetTimeWeek: Date
    public let sourceVersion: String
    public let raw: Data

    public init(timestamp: Date, plan: Plan,
                used5h: Int, ceiling5h: Int, resetTime5h: Date,
                usedWeek: Int, ceilingWeek: Int, resetTimeWeek: Date,
                sourceVersion: String, raw: Data) {
        self.timestamp = timestamp
        self.plan = plan
        self.used5h = used5h; self.ceiling5h = ceiling5h; self.resetTime5h = resetTime5h
        self.usedWeek = usedWeek; self.ceilingWeek = ceilingWeek; self.resetTimeWeek = resetTimeWeek
        self.sourceVersion = sourceVersion
        self.raw = raw
    }

    public var fraction5h: Double {
        guard ceiling5h > 0 else { return 0 }
        return min(1.0, Double(used5h) / Double(ceiling5h))
    }
    public var fractionWeek: Double {
        guard ceilingWeek > 0 else { return 0 }
        return min(1.0, Double(usedWeek) / Double(ceilingWeek))
    }
    public var currentWindowStart5h: Date {
        resetTime5h.addingTimeInterval(-5 * 3600)
    }
}
