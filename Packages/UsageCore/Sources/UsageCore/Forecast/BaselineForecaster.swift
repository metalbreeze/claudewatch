import Foundation

public struct BaselineForecaster {
    public init() {}

    public enum Mode { case twentyFourHour, weekly }
    public enum BaselineNote { case ok, insufficientHistory }

    public struct Bucket: Equatable {
        public let key: Int             // hour 0..23 (24h) or hour-of-week 0..167 (1w)
        public let median: Double       // fraction of ceiling
        public let p25: Double
        public let p75: Double
    }

    public struct Baseline: Equatable {
        public let buckets: [Bucket]
        public let note: BaselineNote
    }

    public func baseline(snapshots: [UsageSnapshot],
                         mode: Mode,
                         now: Date = Date()) -> Baseline {
        // Need at least 3 distinct days of data.
        let cal = Calendar(identifier: .gregorian)
        let days = Set(snapshots.map { cal.startOfDay(for: $0.timestamp) }).count
        guard days >= 3 else { return .init(buckets: [], note: .insufficientHistory) }

        let bucketCount = (mode == .twentyFourHour) ? 24 : 168
        var grouped = [Int: [Double]]()
        for s in snapshots {
            let comps = cal.dateComponents([.weekday, .hour], from: s.timestamp)
            let key = (mode == .twentyFourHour)
                ? (comps.hour ?? 0)
                : ((comps.weekday ?? 1) - 1) * 24 + (comps.hour ?? 0)
            let frac = s.fraction5h
            grouped[key, default: []].append(frac)
        }
        let buckets = (0..<bucketCount).map { k -> Bucket in
            let arr = (grouped[k] ?? []).sorted()
            return Bucket(key: k, median: percentile(arr, 0.5),
                          p25: percentile(arr, 0.25), p75: percentile(arr, 0.75))
        }
        return .init(buckets: buckets, note: .ok)
    }

    private func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let i = Double(sorted.count - 1) * p
        let lo = Int(i.rounded(.down)); let hi = Int(i.rounded(.up))
        if lo == hi { return sorted[lo] }
        let frac = i - Double(lo)
        return sorted[lo] * (1 - frac) + sorted[hi] * frac
    }
}
