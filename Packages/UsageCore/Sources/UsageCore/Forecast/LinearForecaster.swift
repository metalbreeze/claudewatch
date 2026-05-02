import Foundation

public struct LinearForecaster {
    public let halfLifeSeconds: Double = 1800
    public init() {}

    /// Returns nil if fewer than 3 input points.
    public func forecast(snapshots: [UsageSnapshot], now: Date = Date()) -> ForecastResult? {
        guard snapshots.count >= 3 else { return nil }
        guard let last = snapshots.last else { return nil }
        let ceiling = Double(last.ceiling5h)

        let xs = snapshots.map { $0.timestamp.timeIntervalSince(now) }   // negative for past
        let ys = snapshots.map { Double($0.used5h) }
        let ws = xs.map { exp($0 / halfLifeSeconds) }                    // bigger for x≈0

        let sumW = ws.reduce(0, +)
        let mx = zip(xs, ws).map(*).reduce(0,+) / sumW
        let my = zip(ys, ws).map(*).reduce(0,+) / sumW
        let num = zip(zip(xs, ys), ws).map { (xy, w) in w * (xy.0 - mx) * (xy.1 - my) }.reduce(0,+)
        let den = zip(xs, ws).map { (x, w) in w * (x - mx) * (x - mx) }.reduce(0,+)
        guard den > 0 else { return nil }
        let slope = num / den
        let intercept = my - slope * mx     // y at x=0 (now)

        // R²
        let ssTot = zip(ys, ws).map { (y, w) in w * (y - my) * (y - my) }.reduce(0,+)
        var ssRes: Double = 0
        for ((x, y), w) in zip(zip(xs, ys), ws) {
            let pred = slope * x + intercept
            let diff = y - pred
            ssRes += w * diff * diff
        }
        let r2 = ssTot > 0 ? max(0, 1 - ssRes / ssTot) : 0

        // Anchor the forecast at the LAST observed snapshot rather than
        // at `now`. Two reasons:
        //
        //   1. Continuity: callers (e.g. ChartView) draw the forecast as
        //      a separate Swift Charts series alongside the actual-data
        //      line. If the forecast started at `now` with value
        //      `intercept` (the regression's smoothed prediction), there
        //      was a visible gap between the actual line's endpoint
        //      (last.timestamp, last.fraction5h) and the forecast's
        //      start. Anchoring at the last snapshot makes them touch.
        //
        //   2. Honesty: the slope captures the recent rate, but the
        //      regression's intercept can drift slightly from the actual
        //      most-recent measurement. Treating the last data point as
        //      ground truth and projecting forward from THERE matches
        //      what users expect from "predicted line".
        let lastT = last.timestamp
        let lastTokens = Double(last.used5h)

        // Hit time: same math, just relative to lastT instead of now.
        var hit: Date? = nil
        if slope > 0.0001 {
            let secsUntil = (ceiling - lastTokens) / slope
            if secsUntil > 0 && secsUntil < (last.resetTime5h.timeIntervalSince(lastT) + 1) {
                hit = lastT.addingTimeInterval(secsUntil)
            }
        }

        var line: [ForecastPoint] = []
        let endT = hit ?? last.resetTime5h

        // First point: anchor exactly at the last snapshot.
        line.append(.init(time: lastT, projectedFraction: min(1, lastTokens / ceiling)))

        // Subsequent points: project forward in 60s steps using the
        // regression slope (tokens per second) starting from the last
        // measurement.
        var t = lastT.addingTimeInterval(60)
        while t < endT {
            let dt = t.timeIntervalSince(lastT)
            let pred = lastTokens + slope * dt
            line.append(.init(time: t, projectedFraction: min(1, max(0, pred / ceiling))))
            t.addTimeInterval(60)
        }
        return ForecastResult(slope: slope, intercept: intercept,
                              projectedHitTime: hit, line: line, rSquared: r2)
    }
}
