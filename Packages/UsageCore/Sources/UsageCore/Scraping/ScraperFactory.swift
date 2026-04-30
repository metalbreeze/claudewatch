import Foundation

public struct ScraperFactory {
    public let config: EndpointConfig
    public let cookies: CookiePackage
    public let session: URLSession

    public init(config: EndpointConfig, cookies: CookiePackage, session: URLSession = .shared) {
        self.config = config; self.cookies = cookies; self.session = session
    }

    public func current() -> UsageScraper {
        if let url = config.jsonEndpoint {
            return JSONUsageScraper(endpoint: url, cookies: cookies, session: session)
        }
        return HTMLUsageScraper()
    }
}
