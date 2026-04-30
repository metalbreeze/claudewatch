import Foundation

public final class PollingTimer {
    public var onTick: (() -> Void)?
    public let interval: TimeInterval
    public let jitter: TimeInterval
    private var task: Task<Void, Never>?

    public init(interval: TimeInterval, jitter: TimeInterval) {
        self.interval = interval; self.jitter = jitter
    }

    public func nextDelay() -> TimeInterval {
        guard jitter > 0 else { return interval }
        let r = Double.random(in: -jitter...jitter)
        return max(0, interval + r)
    }

    public func start() {
        stop()
        task = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.nextDelay() * 1_000_000_000))
                if Task.isCancelled { return }
                self.onTick?()
            }
        }
    }
    public func stop() { task?.cancel(); task = nil }
}
