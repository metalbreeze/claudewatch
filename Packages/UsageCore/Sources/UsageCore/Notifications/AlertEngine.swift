import Foundation

public protocol AlertStateReader {
    func lastFired(_ kind: AlertKind) -> Date?
    func snoozedUntil(_ kind: AlertKind) -> Date?
}

public struct AlertSettings {
    public var enabled: Set<AlertKind>
    public var quietHoursStartMin: Int  // minutes since midnight
    public var quietHoursEndMin: Int
    public static let `default` = AlertSettings(
        enabled: Set(AlertKind.allCases),
        quietHoursStartMin: 22 * 60,
        quietHoursEndMin: 8 * 60
    )
}

public struct AlertEngine {
    public init() {}

    public func decide(snapshot s: UsageSnapshot,
                       forecast f: ForecastResult?,
                       alertState st: AlertStateReader,
                       settings: AlertSettings,
                       now: Date) -> Set<AlertKind> {
        var fires: Set<AlertKind> = []

        // 5h-forecast
        if settings.enabled.contains(.fiveHourForecast),
           let f, !f.isLowConfidence, let hit = f.projectedHitTime,
           hit.timeIntervalSince(now) <= 15 * 60,
           !alreadyFiredInWindow(.fiveHourForecast, windowStart: s.currentWindowStart5h, st: st) {
            fires.insert(.fiveHourForecast)
        }

        // 5h-hit
        if settings.enabled.contains(.fiveHourHit),
           s.used5h >= s.ceiling5h,
           !alreadyFiredInWindow(.fiveHourHit, windowStart: s.currentWindowStart5h, st: st) {
            fires.insert(.fiveHourHit)
        }

        // weekly thresholds
        if settings.enabled.contains(.weekNinety),
           s.fractionWeek >= 0.9,
           !alreadyFiredInWeek(.weekNinety, weekStart: s.resetTimeWeek.addingTimeInterval(-7*86400), st: st) {
            fires.insert(.weekNinety)
        }
        if settings.enabled.contains(.weekHundred),
           s.usedWeek >= s.ceilingWeek,
           !alreadyFiredInWeek(.weekHundred, weekStart: s.resetTimeWeek.addingTimeInterval(-7*86400), st: st) {
            fires.insert(.weekHundred)
        }

        // honor snoozes
        fires = fires.filter { (st.snoozedUntil($0) ?? .distantPast) < now }

        return fires
    }

    private func alreadyFiredInWindow(_ k: AlertKind, windowStart: Date, st: AlertStateReader) -> Bool {
        guard let last = st.lastFired(k) else { return false }
        return last >= windowStart
    }
    private func alreadyFiredInWeek(_ k: AlertKind, weekStart: Date, st: AlertStateReader) -> Bool {
        guard let last = st.lastFired(k) else { return false }
        return last >= weekStart
    }

    public func isQuietHours(_ now: Date, settings: AlertSettings, calendar: Calendar = .init(identifier: .gregorian)) -> Bool {
        let comps = calendar.dateComponents([.hour, .minute], from: now)
        let m = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let start = settings.quietHoursStartMin, end = settings.quietHoursEndMin
        if start <= end { return m >= start && m < end }
        return m >= start || m < end                 // crosses midnight
    }
}
