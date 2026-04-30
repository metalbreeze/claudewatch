import Foundation

public enum Plan: Equatable, Hashable, Codable {
    case pro
    case max5x
    case max20x
    case team
    case free
    case custom(String)

    public init(rawString: String) {
        switch rawString {
        case "Pro": self = .pro
        case "Max 5x": self = .max5x
        case "Max 20x": self = .max20x
        case "Team": self = .team
        case "Free": self = .free
        default: self = .custom(rawString)
        }
    }

    public var displayName: String {
        switch self {
        case .pro: return "Pro"
        case .max5x: return "Max 5x"
        case .max20x: return "Max 20x"
        case .team: return "Team"
        case .free: return "Free"
        case .custom(let s): return s
        }
    }
}
