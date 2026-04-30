import AppKit
import WebKit
import UsageCore

/// Silently re-acquires `cf_clearance` from Cloudflare by loading
/// claude.ai in a 1×1 hidden WKWebView. Cloudflare runs a JS challenge
/// that URLSession can't pass; WKWebView passes it transparently. Once
/// the page loads, we pull the fresh cf_clearance / __cf_bm cookies and
/// merge them into the stored CookiePackage.
@MainActor
final class HiddenChallengeView {
    static func refreshClearance(into store: CookiePackageStore,
                                 currentDeviceID: String) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let cfg = WKWebViewConfiguration()
            let webView = WKWebView(frame: .init(x: 0, y: 0, width: 1, height: 1),
                                    configuration: cfg)
            // Match the Safari UA used in the visible login WebView so
            // Cloudflare's fingerprint stays consistent across both
            // surfaces.
            webView.customUserAgent = LoginWebView.safariUserAgent
            // Hold a strong reference until the navigation completes.
            var holder: WKWebView? = webView

            class Delegate: NSObject, WKNavigationDelegate {
                let onDone: (Bool) -> Void
                let store: CookiePackageStore
                init(_ store: CookiePackageStore, _ onDone: @escaping (Bool) -> Void) {
                    self.store = store; self.onDone = onDone
                }
                func webView(_ wv: WKWebView, didFinish nav: WKNavigation!) {
                    Task {
                        let cookies = await wv.configuration.websiteDataStore
                            .httpCookieStore.allCookies()
                        wv.evaluateJavaScript("navigator.userAgent") { v, _ in
                            let ua = (v as? String) ?? "Mozilla/5.0"
                            let new = CookieReader.package(from: cookies, userAgent: ua)
                            if let existing = try? self.store.load() {
                                var merged = existing
                                merged.cfClearance = new.cfClearance ?? merged.cfClearance
                                merged.cfBm = new.cfBm ?? merged.cfBm
                                merged.userAgent = ua
                                try? self.store.save(merged)
                                self.onDone(merged.cfClearance != nil)
                            } else { self.onDone(false) }
                        }
                    }
                }
                func webView(_ wv: WKWebView, didFail nav: WKNavigation!, withError error: Error) {
                    onDone(false)
                }
            }

            let del = Delegate(store) { ok in
                holder = nil
                cont.resume(returning: ok)
            }
            webView.navigationDelegate = del
            // Keep the delegate alive for the duration of the navigation.
            objc_setAssociatedObject(webView, "del", del, .OBJC_ASSOCIATION_RETAIN)
            webView.load(URLRequest(url: URL(string: "https://claude.ai/")!))
        }
    }
}
