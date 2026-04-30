import Foundation

public struct CookiePackage: Codable, Equatable {
    public var sessionKey: String?
    public var cfClearance: String?
    public var cfBm: String?
    public var userAgent: String
    public var all: [SerializedCookie]

    public init(sessionKey: String?, cfClearance: String?, cfBm: String?,
                userAgent: String, all: [SerializedCookie]) {
        self.sessionKey = sessionKey
        self.cfClearance = cfClearance
        self.cfBm = cfBm
        self.userAgent = userAgent
        self.all = all
    }

    public struct SerializedCookie: Codable, Equatable {
        public let name: String
        public let value: String
        public let domain: String
        public let path: String
        public let isSecure: Bool
        public let isHTTPOnly: Bool
        public let expiresAt: Date?

        public init(name: String, value: String,
                    domain: String, path: String,
                    isSecure: Bool, isHTTPOnly: Bool,
                    expiresAt: Date?) {
            self.name = name; self.value = value
            self.domain = domain; self.path = path
            self.isSecure = isSecure; self.isHTTPOnly = isHTTPOnly
            self.expiresAt = expiresAt
        }
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
