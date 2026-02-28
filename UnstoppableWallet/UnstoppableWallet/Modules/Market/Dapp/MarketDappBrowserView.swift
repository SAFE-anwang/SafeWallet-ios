import SwiftUI
@preconcurrency import WebKit

struct MarketDappBrowserView: View {
    let url: URL
    let onClose: () -> Void

    var body: some View {
        ThemeNavigationStack {
            ThemeView {
                MarketDappWebView(url: url)
            }
            .navigationTitle(url.host ?? "")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("button.close".localized) {
                        onClose()
                    }
                }
            }
        }
    }
}

struct MarketDappWebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.allowsBackForwardNavigationGestures = true
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastLoadedUrl != url {
            webView.load(URLRequest(url: url))
            context.coordinator.lastLoadedUrl = url
        }
    }

    class Coordinator: NSObject {
        var lastLoadedUrl: URL?
    }
}

enum MarketDappBrowserUrlParser {
    static func url(string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let withScheme: String
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            withScheme = trimmed
        } else {
            withScheme = "https://\(trimmed)"
        }

        return URL(string: withScheme)
    }
}
