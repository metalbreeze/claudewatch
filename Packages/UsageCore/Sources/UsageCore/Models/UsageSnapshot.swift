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

    /// Fable is a per-model *weekly* limit Anthropic reports in the
    /// `limits[]` array as `kind == "weekly_scoped"`. Not every account
    /// has one, so all three fields degrade to nil/false rather than
    /// zero — the UI hides the gauge entirely when `usedFable` is nil,
    /// which is meaningfully different from "you have a Fable limit and
    /// have used 0% of it".
    ///
    /// Same 0–10000 scale as `used5h` / `usedWeek` (percent × 100), so
    /// the shared ceiling of 10_000 applies.
    public let usedFable: Int?
    public let resetTimeFable: Date?
    /// Anthropic's `is_active` flag: true when this is the limit
    /// currently throttling the account. Surfaced so the UI can point
    /// at the gauge that actually matters.
    public let fableIsActive: Bool

    public init(timestamp: Date, plan: Plan,
                used5h: Int, ceiling5h: Int, resetTime5h: Date,
                usedWeek: Int, ceilingWeek: Int, resetTimeWeek: Date,
                sourceVersion: String, raw: Data,
                usedFable: Int? = nil,
                resetTimeFable: Date? = nil,
                fableIsActive: Bool = false) {
        self.timestamp = timestamp
        self.plan = plan
        self.used5h = used5h; self.ceiling5h = ceiling5h; self.resetTime5h = resetTime5h
        self.usedWeek = usedWeek; self.ceilingWeek = ceilingWeek; self.resetTimeWeek = resetTimeWeek
        self.sourceVersion = sourceVersion
        self.raw = raw
        self.usedFable = usedFable
        self.resetTimeFable = resetTimeFable
        self.fableIsActive = fableIsActive
    }

    public var fraction5h: Double {
        guard ceiling5h > 0 else { return 0 }
        return min(1.0, Double(used5h) / Double(ceiling5h))
    }
    public var fractionWeek: Double {
        guard ceilingWeek > 0 else { return 0 }
        return min(1.0, Double(usedWeek) / Double(ceilingWeek))
    }
    /// nil when the account has no Fable limit — callers use that to
    /// decide whether to render the Fable gauge at all.
    public var fractionFable: Double? {
        guard let u = usedFable else { return nil }
        return min(1.0, Double(u) / 10_000)
    }
    public var currentWindowStart5h: Date {
        resetTime5h.addingTimeInterval(-5 * 3600)
    }
}
