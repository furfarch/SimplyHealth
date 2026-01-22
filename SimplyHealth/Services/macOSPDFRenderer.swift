#if os(macOS)
import Foundation
import WebKit

enum macOSPDFRenderer {
    static func render(html: String) async throws -> Data {
        let webView = WKWebView(frame: .zero)

        let navigationDelegate = NavigationDelegate()
        webView.navigationDelegate = navigationDelegate

        navigationDelegate.load(html: html, in: webView)
        try await navigationDelegate.didFinish

        let config = WKPDFConfiguration()
        return try await webView.pdf(configuration: config)
    }

    private final class NavigationDelegate: NSObject, WKNavigationDelegate {
        private var continuation: CheckedContinuation<Void, Error>?
        var didFinish: Void {
            get async throws {
                try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                    continuation = c
                }
            }
        }

        func load(html: String, in webView: WKWebView) {
            webView.loadHTMLString(html, baseURL: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            continuation?.resume()
            continuation = nil
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            continuation?.resume(throwing: error)
            continuation = nil
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
#endif
