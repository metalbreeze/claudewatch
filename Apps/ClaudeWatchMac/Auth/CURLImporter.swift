import Foundation
import UsageCore

/// Parsed result of a `curl` command — used by `CURLImportWindow` to drop
/// in cookies + endpoint extracted from a real browser session, bypassing
/// the broken-by-Cloudflare-and-Google embedded WKWebView login.
public struct CURLImport {
    public let url: URL
    public let headers: [String: String]
    public let method: String

    /// Cookies parsed from `Cookie:` header (or `-b/--cookie` flag).
    public var cookies: [String: String] {
        let raw = headers["cookie"] ?? headers["Cookie"] ?? ""
        var dict: [String: String] = [:]
        for part in raw.split(separator: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if let eq = trimmed.firstIndex(of: "=") {
                let k = String(trimmed[..<eq])
                let v = String(trimmed[trimmed.index(after: eq)...])
                dict[k] = v
            }
        }
        return dict
    }

    public var userAgent: String? {
        headers["user-agent"] ?? headers["User-Agent"]
    }
}

public enum CURLParseError: Error, CustomStringConvertible {
    case notCurl
    case noURL
    case wrongHost(String)
    case wrongPath(String)
    case missingSessionKey

    public var description: String {
        switch self {
        case .notCurl:
            return String(localized: "cURL.error.notCurl",
                defaultValue: "Doesn't look like a curl command — must start with 'curl '.")
        case .noURL:
            return String(localized: "cURL.error.noURL",
                defaultValue: "No URL found in the command.")
        case .wrongHost(let host):
            return String(localized: "cURL.error.wrongHost \(host)" as String.LocalizationValue)
        case .wrongPath(let path):
            return String(localized: "cURL.error.wrongPath \(path)" as String.LocalizationValue)
        case .missingSessionKey:
            return String(localized: "cURL.error.missingSessionKey",
                defaultValue: "No 'sessionKey' cookie found. Make sure you copied the cURL from a request to claude.ai while signed in.")
        }
    }
}

public enum CURLParser {
    /// Parses a `curl` command (single-line or multi-line with backslash
    /// continuations) into URL + headers + method. Tolerant of single
    /// vs double quotes and most common curl flags.
    public static func parse(_ raw: String) throws -> CURLImport {
        // Strip line continuations: backslash-newline => space.
        let normalized = raw.replacingOccurrences(of: "\\\n", with: " ")
        let tokens = tokenize(normalized)
        guard let first = tokens.first, first.lowercased().hasSuffix("curl") else {
            throw CURLParseError.notCurl
        }
        var url: URL?
        var headers: [String: String] = [:]
        var method = "GET"
        var i = 1
        while i < tokens.count {
            let t = tokens[i]
            switch t {
            case "-H", "--header":
                i += 1
                guard i < tokens.count else { break }
                let header = tokens[i]
                if let colon = header.firstIndex(of: ":") {
                    let name = String(header[..<colon])
                        .trimmingCharacters(in: .whitespaces)
                        .lowercased()
                    let value = String(header[header.index(after: colon)...])
                        .trimmingCharacters(in: .whitespaces)
                    headers[name] = value
                }
            case "-X", "--request":
                i += 1
                if i < tokens.count { method = tokens[i] }
            case "-b", "--cookie":
                i += 1
                if i < tokens.count { headers["cookie"] = tokens[i] }
            case "-d", "--data", "--data-raw", "--data-binary":
                i += 1                 // skip POST body
                if method == "GET" { method = "POST" }
            case "--compressed", "-L", "--location",
                 "--insecure", "-k",
                 "-A", "--user-agent":
                if t == "-A" || t == "--user-agent" {
                    i += 1
                    if i < tokens.count { headers["user-agent"] = tokens[i] }
                }
            default:
                if !t.hasPrefix("-"),
                   url == nil,
                   let u = URL(string: t),
                   u.scheme != nil {
                    url = u
                }
            }
            i += 1
        }
        guard let url else { throw CURLParseError.noURL }
        return CURLImport(url: url, headers: headers, method: method)
    }

    /// Shell-style tokenizer respecting single-quoted and double-quoted
    /// strings and backslash-escapes outside single quotes.
    static func tokenize(_ s: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inSingle = false
        var inDouble = false
        var escaped = false
        for c in s {
            if escaped {
                current.append(c)
                escaped = false
                continue
            }
            if c == "\\" {
                if inSingle {
                    current.append(c)        // single quotes preserve backslash
                } else {
                    escaped = true
                }
                continue
            }
            if c == "'" && !inDouble {
                inSingle.toggle()
                continue
            }
            if c == "\"" && !inSingle {
                inDouble.toggle()
                continue
            }
            if c.isWhitespace && !inSingle && !inDouble {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }
            current.append(c)
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}

/// Applies a `CURLImport` to the running app: persists the cookie
/// package + endpoint URL, then nudges the AppDelegate to restart polling.
enum CURLImportApplier {
    static func apply(_ imp: CURLImport, ctx: AppContext) throws {
        // Defense-in-depth: re-validate even though the UI also checks.
        // A future programmatic caller (CLI, scripted import, tests)
        // shouldn't need to know to validate — `apply` enforces it.
        guard let host = imp.url.host?.lowercased(),
              host.contains("claude.ai") else {
            throw CURLParseError.wrongHost(imp.url.host ?? "")
        }
        guard imp.url.path.lowercased().contains("usage") else {
            throw CURLParseError.wrongPath(imp.url.path)
        }
        let cookies = imp.cookies
        guard cookies["sessionKey"] != nil else {
            throw CURLParseError.missingSessionKey
        }

        // Build typed CookiePackage
        var pkg = CookiePackage(
            sessionKey: cookies["sessionKey"],
            cfClearance: cookies["cf_clearance"],
            cfBm: cookies["__cf_bm"],
            userAgent: imp.userAgent ?? "Mozilla/5.0",
            all: [])
        for (name, value) in cookies {
            pkg.all.append(.init(
                name: name, value: value,
                domain: ".claude.ai", path: "/",
                isSecure: true, isHTTPOnly: false, expiresAt: nil))
        }
        try ctx.cookieStore.save(pkg)

        // Persist the discovered endpoint URL
        try ctx.settings.set(.endpointConfig, imp.url.absoluteString)
    }
}
