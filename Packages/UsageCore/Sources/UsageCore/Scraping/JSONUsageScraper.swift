import Foundation

public struct JSONUsageScraper: UsageScraper {
    public let sourceVersion = "json-v1"
    public let endpoint: URL
    public let cookies: CookiePackage
    public let session: URLSession

    public init(endpoint: URL, cookies: CookiePackage, session: URLSession = .shared) {
        self.endpoint = endpoint; self.cookies = cookies; self.session = session
    }

    private struct Response: Decodable {
        let plan: String
        let fiveHourWindow: Window
        let weeklyWindow: Window
        struct Window: Decodable {
            let used: Int
            let limit: Int
            let resetAt: Date
        }
    }

    public func fetchSnapshot() async throws -> UsageSnapshot {
        var req = URLRequest(url: endpoint)
        req.timeoutInterval = 15
        req.setValue(cookies.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue(buildCookieHeader(), forHTTPHeaderField: "Cookie")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await session.data(for: req) }
        catch let e as URLError { throw ScrapeError.network(e) }

        guard let http = resp as? HTTPURLResponse else { throw ScrapeError.unknown("no HTTP response") }
        switch http.statusCode {
        case 200: break
        case 401, 403:
            if let txt = String(data: data, encoding: .utf8), txt.contains("Just a moment") || txt.contains("cf-challenge") {
                throw ScrapeError.cloudflareChallenge
            }
            throw ScrapeError.authExpired
        case 429:
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw ScrapeError.rateLimited(retryAfter: retry)
        default:
            throw ScrapeError.unknown("HTTP \(http.statusCode)")
        }

        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        do {
            let r = try dec.decode(Response.self, from: data)
            return UsageSnapshot(
                timestamp: Date(),
                plan: Plan(rawString: r.plan),
                used5h: r.fiveHourWindow.used,
                ceiling5h: r.fiveHourWindow.limit,
                resetTime5h: r.fiveHourWindow.resetAt,
                usedWeek: r.weeklyWindow.used,
                ceilingWeek: r.weeklyWindow.limit,
                resetTimeWeek: r.weeklyWindow.resetAt,
                sourceVersion: sourceVersion,
                raw: data)
        } catch {
            throw ScrapeError.schemaDrift(version: sourceVersion, payload: data)
        }
    }

    private func buildCookieHeader() -> String {
        var parts: [String] = []
        if let s = cookies.sessionKey { parts.append("sessionKey=\(s)") }
        if let c = cookies.cfClearance { parts.append("cf_clearance=\(c)") }
        if let b = cookies.cfBm { parts.append("__cf_bm=\(b)") }
        return parts.joined(separator: "; ")
    }
}
