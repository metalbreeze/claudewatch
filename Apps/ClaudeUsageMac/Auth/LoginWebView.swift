import AppKit
import WebKit
import UsageCore

/// Hosts a WKWebView that loads claude.ai/login. When the user finishes
/// signing in (detected by navigation away from /login while still on
/// claude.ai), pulls cookies + UA from the WKWebView and invokes
/// `onSuccess` with a `CookiePackage`.
final class LoginWebView: NSView, WKNavigationDelegate {
    let webView: WKWebView
    let onSuccess: (CookiePackage) -> Void
    private var didFire = false

    /// Real Safari user-agent. Google's OAuth flow detects WKWebView's
    /// default UA and refuses with "This browser may not be secure" /
    /// `disallowed_useragent`. Pretending to be Safari makes the embedded
    /// flow work for Google SSO. The same UA is later persisted in the
    /// CookiePackage so URLSession polls stay consistent.
    static let safariUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    init(onSuccess: @escaping (CookiePackage) -> Void) {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        // applicationNameForUserAgent is appended to WKWebView's default UA
        // and isn't enough to fool Google. Set customUserAgent on the
        // WKWebView itself once it exists (below).
        self.webView = WKWebView(frame: .zero, configuration: cfg)
        self.webView.customUserAgent = Self.safariUserAgent
        self.onSuccess = onSuccess
        super.init(frame: .zero)
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        webView.navigationDelegate = self
        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
    }

    required init?(coder: NSCoder) { fatalError() }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url else { return }
        // Successful login redirects away from /login (e.g. to /chats or
        // /new). The first such navigation captures the auth cookie.
        if !didFire,
           !url.path.contains("/login"),
           url.host?.contains("claude.ai") == true {
            didFire = true
            Task {
                let cookies = await webView.configuration.websiteDataStore
                    .httpCookieStore.allCookies()
                // The webview's customUserAgent overrides what JS sees,
                // so navigator.userAgent already reports our spoofed
                // Safari UA — matching what URLSession will send later.
                webView.evaluateJavaScript("navigator.userAgent") { value, _ in
                    let ua = (value as? String) ?? Self.safariUserAgent
                    let pkg = CookieReader.package(from: cookies, userAgent: ua)
                    self.onSuccess(pkg)
                }
            }
        }
    }
}
