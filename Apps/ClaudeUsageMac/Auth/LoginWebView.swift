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

    init(onSuccess: @escaping (CookiePackage) -> Void) {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        // Important: do NOT set customUserAgent here. We tried spoofing
        // a Safari UA to make Google OAuth work, but it broke Cloudflare's
        // bot-detection (the UA-vs-fingerprint mismatch traps you in a
        // captcha loop). Use email login on claude.ai instead — Google
        // SSO in embedded webviews is fundamentally unsupported by Google
        // since 2019 and any workaround conflicts with Cloudflare.
        self.webView = WKWebView(frame: .zero, configuration: cfg)
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

        // Wipe any stale claude.ai data left over from a prior failed
        // login attempt (cf_clearance, __cf_bm, partial sessions, captcha
        // tokens). Without this, an aborted attempt poisons subsequent
        // ones and Cloudflare keeps challenging.
        let store = WKWebsiteDataStore.default()
        let types: Set<String> = [
            WKWebsiteDataTypeCookies,
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeSessionStorage,
            WKWebsiteDataTypeIndexedDBDatabases,
            WKWebsiteDataTypeServiceWorkerRegistrations,
        ]
        store.fetchDataRecords(ofTypes: types) { records in
            let claudeRecords = records.filter {
                $0.displayName.contains("claude.ai") ||
                $0.displayName.contains("anthropic")
            }
            store.removeData(ofTypes: types, for: claudeRecords) { [weak self] in
                guard let self else { return }
                self.webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
            }
        }
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
                webView.evaluateJavaScript("navigator.userAgent") { value, _ in
                    let ua = (value as? String) ?? "Mozilla/5.0"
                    let pkg = CookieReader.package(from: cookies, userAgent: ua)
                    self.onSuccess(pkg)
                }
            }
        }
    }
}
