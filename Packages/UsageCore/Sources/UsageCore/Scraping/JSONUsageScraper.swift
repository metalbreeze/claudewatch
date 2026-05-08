import Foundation

public struct JSONUsageScraper: UsageScraper {
    public let sourceVersion = "json-v2"
    public let endpoint: URL
    public let cookies: CookiePackage
    public let session: URLSession

    public init(endpoint: URL, cookies: CookiePackage, session: URLSession = .shared) {
        self.endpoint = endpoint; self.cookies = cookies; self.session = session
    }

    /// Real shape of `claude.ai/api/organizations/{org_id}/usage` (observed
    /// 2026-04-30). Anthropic exposes utilization as a percentage (0–100)
    /// rather than raw token counts. We fold both into our snapshot's
    /// `used / ceiling` model by setting ceiling = 10000 and storing
    /// `used = round(utilization * 100)` so 0.01% of precision is kept.
    /// The JSON also includes per-model windows (sonnet/opus/oauth_apps/
    /// cowork/omelette) and an `extra_usage` block that we ignore for
    /// the v1 product surface.
    private struct Response: Decodable {
        let five_hour: Window?
        let seven_day: Window?
        struct Window: Decodable {
            let utilization: Double
            let resets_at: Date?
        }
    }

    public func fetchSnapshot() async throws -> UsageSnapshot {
        var req = URLRequest(url: endpoint)
        req.timeoutInterval = 15
        // Mirror what claude.ai's browser fetch sends, so the request
        // doesn't stand out to Cloudflare's bot detection. Anything
        // already set as a typed field (User-Agent, Cookie) overrides
        // these; everything else is a "look like a real browser"
        // signal that helps us pass the lighter CF challenge variants.
        req.setValue(cookies.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue(buildCookieHeader(), forHTTPHeaderField: "Cookie")
        req.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        req.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        req.setValue("https://claude.ai/settings/usage", forHTTPHeaderField: "Referer")
        req.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")
        req.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        req.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        req.setValue("web_claude_ai", forHTTPHeaderField: "anthropic-client-platform")
        // anthropic-device-id is in the cookie jar, but Anthropic's
        // backend also expects it as an explicit header on
        // authenticated calls. Forward it if the user's cURL paste
        // captured one.
        if let dev = cookies.all.first(where: { $0.name == "anthropic-device-id" })?.value {
            req.setValue(dev, forHTTPHeaderField: "anthropic-device-id")
        }

        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await session.data(for: req) }
        catch let e as URLError { throw ScrapeError.network(e) }

        guard let http = resp as? HTTPURLResponse else { throw ScrapeError.unknown("no HTTP response") }
        switch http.statusCode {
        case 200: break
        case 401, 403:
            if isCloudflareChallenge(response: http, body: data) {
                throw ScrapeError.cloudflareChallenge
            }
            throw ScrapeError.authExpired
        case 429:
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw ScrapeError.rateLimited(retryAfter: retry)
        default:
            throw ScrapeError.unknown("HTTP \(http.statusCode)")
        }

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let s = try container.decode(String.self)
            if let d = Self.parseISODate(s) { return d }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unparseable date: \(s)")
        }

        do {
            let r = try dec.decode(Response.self, from: data)
            let now = Date()
            let used5h = Int(((r.five_hour?.utilization ?? 0) * 100).rounded())
            let usedWeek = Int(((r.seven_day?.utilization ?? 0) * 100).rounded())
            return UsageSnapshot(
                timestamp: now,
                // The /usage endpoint doesn't include the plan tier;
                // we surface "—" until/unless we wire a separate
                // /api/account or /api/organizations/{id} call.
                plan: .custom("—"),
                used5h: used5h,
                ceiling5h: 10_000,        // 100.00% scaled by 100
                resetTime5h: r.five_hour?.resets_at ?? now.addingTimeInterval(5 * 3600),
                usedWeek: usedWeek,
                ceilingWeek: 10_000,
                resetTimeWeek: r.seven_day?.resets_at ?? now.addingTimeInterval(7 * 86400),
                sourceVersion: sourceVersion,
                raw: data)
        } catch {
            throw ScrapeError.schemaDrift(version: sourceVersion, payload: data)
        }
    }

    /// Parses ISO 8601 strings with arbitrary fractional-second precision
    /// (Anthropic emits microseconds, e.g. `2026-04-30T19:09:59.955046+00:00`).
    /// `ISO8601DateFormatter` only handles up to milliseconds, so we
    /// truncate the fractional component to 3 digits before parsing.
    private static func parseISODate(_ s: String) -> Date? {
        let truncated = truncateFractional(s)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: truncated) { return d }
        formatter.formatOptions = [.withInternetDateTime]
        // After truncation a now-empty fractional may leave a stray dot.
        let withoutFrac = truncated.replacingOccurrences(
            of: #"\.\d*"#, with: "", options: .regularExpression)
        return formatter.date(from: withoutFrac) ?? formatter.date(from: truncated)
    }

    /// `2026-04-30T19:09:59.955046+00:00` → `2026-04-30T19:09:59.955+00:00`
    private static func truncateFractional(_ s: String) -> String {
        // Find ".<digits>" and keep at most 3 digits.
        guard let pattern = try? NSRegularExpression(pattern: #"\.(\d{1,6})"#) else { return s }
        let range = NSRange(s.startIndex..., in: s)
        return pattern.stringByReplacingMatches(
            in: s, range: range, withTemplate: ".$1") // capture group is already limited below
            .replacingOccurrences(
                of: #"\.(\d{3})\d+"#,
                with: ".$1",
                options: .regularExpression)
    }

    /// Send every cookie the user pasted, not just the 3 we type-pulled
    /// (sessionKey / cf_clearance / __cf_bm). A real browser sends every
    /// cookie it has for the domain — restricting to 3 makes the request
    /// look bot-like to Cloudflare and can also drop fields Anthropic's
    /// backend expects (lastActiveOrg, anthropic-device-id, routingHint,
    /// activitySessionId, etc.). The cookies in `cookies.all` were
    /// captured from a successful claude.ai session, so they're scoped
    /// correctly already.
    private func buildCookieHeader() -> String {
        cookies.all
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
    }

    /// Returns true if a 401/403 response is actually a Cloudflare
    /// challenge rather than a true Anthropic auth rejection.
    ///
    /// We layer three signals from cheapest/most-reliable to most-fuzzy:
    ///
    ///   1. **`cf-mitigated` response header.** Cloudflare sets this
    ///      whenever it injects a challenge or block, regardless of
    ///      which challenge variant (managed / JS / Turnstile / hCaptcha).
    ///      This is the only signal we'd normally need, but older
    ///      Cloudflare zones don't emit it — keep the fallbacks.
    ///
    ///   2. **`server: cloudflare` + non-JSON `content-type`.**
    ///      A 401/403 served BY Cloudflare with HTML/text body is
    ///      always a CF action, never an Anthropic one. Anthropic's
    ///      true 401s come back with `application/json`.
    ///
    ///   3. **Body string match.** The legacy classic — covers any
    ///      challenge HTML that lacks `cf-mitigated` AND somehow has
    ///      a JSON content-type. Unlikely but cheap to keep.
    private func isCloudflareChallenge(response: HTTPURLResponse,
                                       body: Data) -> Bool {
        if let mit = response.value(forHTTPHeaderField: "cf-mitigated"),
           !mit.isEmpty {
            return true
        }
        let server = (response.value(forHTTPHeaderField: "Server") ?? "").lowercased()
        let ctype  = (response.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        if server.contains("cloudflare") && !ctype.contains("application/json") {
            return true
        }
        if let txt = String(data: body, encoding: .utf8) {
            // Common substrings across CF challenge page variants.
            let markers = [
                "Just a moment",
                "cf-challenge",
                "Verify you are human",
                "Checking your browser",
                "challenges.cloudflare.com",
            ]
            for m in markers where txt.contains(m) { return true }
        }
        return false
    }
}
