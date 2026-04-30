import Foundation

public struct ForecastPoint: Equatable, Codable {
    public let time: Date
    public let projectedFraction: Double
    public init(time: Date, projectedFraction: Double) {
        self.time = time; self.projectedFraction = projectedFraction
    }
}

public struct ForecastResult: Equatable, Codable {
    public let slope: Double          // tokens/sec
    public let intercept: Double      // tokens at now
    public let projectedHitTime: Date?
    public let line: [ForecastPoint]
    public let rSquared: Double

    public static let lowConfidenceThreshold: Double = 0.5

    public var isLowConfidence: Bool { rSquared < Self.lowConfidenceThreshold }

    public init(slope: Double, intercept: Double, projectedHitTime: Date?, line: [ForecastPoint], rSquared: Double) {
        self.slope = slope; self.intercept = intercept
        self.projectedHitTime = projectedHitTime
        self.line = line; self.rSquared = rSquared
    }
}
