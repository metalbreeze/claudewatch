import Foundation

public struct CookiePackage: Codable, Equatable {
    public var sessionKey: String?
    public var cfClearance: String?
    public var cfBm: String?
    public var userAgent: String
    public var all: [SerializedCookie]

    public struct SerializedCookie: Codable, Equatable {
        public let name: String
        public let value: String
        public let domain: String
        public let path: String
        public let isSecure: Bool
        public let isHTTPOnly: Bool
        public let expiresAt: Date?
    }
}

public enum CookieReader {
    public static func package(from cookies: [HTTPCookie], userAgent: String) -> CookiePackage {
        var pkg = CookiePackage(sessionKey: nil, cfClearance: nil, cfBm: nil, userAgent: userAgent, all: [])
        for c in cookies {
            switch c.name {
            case "sessionKey": pkg.sessionKey = c.value
            case "cf_clearance": pkg.cfClearance = c.value
            case "__cf_bm": pkg.cfBm = c.value
            default: break
            }
            pkg.all.append(.init(
                name: c.name, value: c.value, domain: c.domain, path: c.path,
                isSecure: c.isSecure, isHTTPOnly: c.isHTTPOnly, expiresAt: c.expiresDate))
        }
        return pkg
    }
}
