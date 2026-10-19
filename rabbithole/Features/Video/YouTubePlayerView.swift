import SwiftUI
import WebKit

/// The official YouTube embedded player (IFrame Player API) in a WKWebView.
///
/// - The player is used unmodified: no overlays, no hidden controls, no autoplay.
/// - YouTube requires embeds to identify the app via the HTTP Referer, otherwise playback
///   fails with error 152/153. The page is therefore loaded with an https base URL derived
///   from the bundle id, which WebKit sends as the referrer origin; `origin` matches it.
/// - Player errors (2, 5, 100, 101, 150, 152, 153 – removed, private, not embeddable…) are reported
///   through `onError` so the card can be skipped quietly.
struct YouTubePlayerView: UIViewRepresentable {
    let videoID: String
    let onError: (Int) -> Void

    static var origin: String {
        "https://\(Bundle.main.bundleIdentifier ?? "app.rabbithole")"
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onError: onError)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.userContentController.add(context.coordinator, name: Coordinator.messageName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        webView.loadHTMLString(Self.html(videoID: videoID), baseURL: URL(string: Self.origin))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.messageName)
        webView.stopLoading()
    }

    /// Only the video id (validated) is interpolated into the page.
    static func html(videoID: String) -> String {
        let safeID = videoID.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return """
        <!DOCTYPE html>
        <html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>html,body{margin:0;height:100%;background:#000}#player{width:100%;height:100%}</style>
        </head><body>
        <div id="player"></div>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
        function onYouTubeIframeAPIReady() {
          new YT.Player('player', {
            width: '100%', height: '100%', videoId: '\(safeID)',
            playerVars: { playsinline: 1, origin: '\(origin)' },
            events: {
              onError: function (event) {
                window.webkit.messageHandlers.\(Coordinator.messageName).postMessage({ error: event.data });
              }
            }
          });
        }
        </script>
        </body></html>
        """
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        static let messageName = "player"
        let onError: (Int) -> Void

        init(onError: @escaping (Int) -> Void) {
            self.onError = onError
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let code = body["error"] as? Int else { return }
            onError(code)
        }

        /// Keep the player page; links the player opens itself (YouTube logo, title) go to Safari/YouTube.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            let isMainFrame = action.targetFrame?.isMainFrame ?? true
            guard isMainFrame, action.navigationType == .linkActivated || action.targetFrame == nil,
                  let url = action.request.url else {
                return .allow
            }
            await UIApplication.shared.open(url)
            return .cancel
        }
    }
}
