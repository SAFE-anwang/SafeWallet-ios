import Foundation
import SwiftUI
import UIKit
@preconcurrency import WebKit

struct MarketDappBrowserConnectInfo: Equatable {
    let chainId: Int
    let address: String
}

struct MarketDappBrowserView: View {
    let url: URL
    let connectInfo: MarketDappBrowserConnectInfo?
    let onClose: () -> Void
    @StateObject private var web3Handler: MarketDappWeb3Handler
    @State private var progress: Double = 0
    @State private var isLoading = false

    init(url: URL, connectInfo: MarketDappBrowserConnectInfo?, onClose: @escaping () -> Void) {
        self.url = url
        self.connectInfo = connectInfo
        self.onClose = onClose

        let chainId = connectInfo?.chainId ?? 1
        let address = connectInfo?.address ?? ""
        _web3Handler = StateObject(wrappedValue: MarketDappWeb3Handler(chainId: chainId, address: address, dAppName: url.host ?? ""))
    }

    var body: some View {
        ThemeNavigationStack {
            ThemeView {
                VStack(spacing: 0) {
                    if isLoading, progress < 1 {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(.themeYellow)
                            .frame(height: 1)
                            .padding(.horizontal, .margin4)
                            .padding(.top, .margin8)
                            .padding(.bottom, .margin8)
                    }

                    MarketDappWebView(
                        url: url,
                        connectInfo: connectInfo,
                        web3Handler: connectInfo == nil ? nil : web3Handler,
                        progress: $progress,
                        isLoading: $isLoading
                    )
                }
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
        .sheet(item: $web3Handler.destination, onDismiss: {
            web3Handler.handlePresentedDismiss()
        }) { destination in
            SendEvmConfirmationView(viewController: destination.viewController)
        }
    }
}

struct MarketDappWebView: UIViewRepresentable {
    let url: URL
    let connectInfo: MarketDappBrowserConnectInfo?
    let web3Handler: MarketDappWeb3Handler?
    @Binding var progress: Double
    @Binding var isLoading: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onProgress: { progress in
                self.progress = progress
            },
            onLoadingChanged: { isLoading in
                self.isLoading = isLoading
            }
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView: WKWebView
        if let connectInfo, let web3Handler {
            let config = WKWebViewConfiguration.make(forChainId: connectInfo.chainId, address: connectInfo.address, messageHandler: web3Handler)
            config.websiteDataStore = WKWebsiteDataStore.default()
            webView = WKWebView(frame: .zero, configuration: config)
        } else {
            webView = WKWebView()
        }

        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.bind(webView: webView)
        web3Handler?.bind(webView: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastLoadedUrl != url {
            progress = 0
            webView.load(URLRequest(url: url))
            context.coordinator.lastLoadedUrl = url
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var lastLoadedUrl: URL?
        private let onProgress: (Double) -> Void
        private let onLoadingChanged: (Bool) -> Void
        private var progressObservation: NSKeyValueObservation?

        init(onProgress: @escaping (Double) -> Void, onLoadingChanged: @escaping (Bool) -> Void) {
            self.onProgress = onProgress
            self.onLoadingChanged = onLoadingChanged
        }

        func bind(webView: WKWebView) {
            progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.onProgress(webView.estimatedProgress)
                }
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.onLoadingChanged(true)
                self.onProgress(webView.estimatedProgress)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.onProgress(1)
                self.onLoadingChanged(false)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.onLoadingChanged(false)
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.onLoadingChanged(false)
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if let uri = walletConnectUri(url: url) {
                Task { @MainActor in
                    try? await Core.shared.appEventHandler.handle(source: .main, event: uri, eventType: .walletConnectUri)
                }
                decisionHandler(.cancel)
                return
            }

            if shouldOpenExternally(url: url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard navigationAction.targetFrame == nil, let url = navigationAction.request.url else {
                return nil
            }

            if let uri = walletConnectUri(url: url) {
                Task { @MainActor in
                    try? await Core.shared.appEventHandler.handle(source: .main, event: uri, eventType: .walletConnectUri)
                }
                return nil
            }

            if shouldOpenExternally(url: url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            } else {
                webView.load(URLRequest(url: url))
            }

            return nil
        }

        private func shouldOpenExternally(url: URL) -> Bool {
            if let scheme = url.scheme?.lowercased(), scheme != "http", scheme != "https" {
                return scheme != "about"
            }

            let host = url.host?.lowercased()
            if host == "metamask.app.link" || host == "link.walletconnect.com" {
                return true
            }

            return false
        }

        private func walletConnectUri(url: URL) -> String? {
            if url.scheme?.lowercased() == "wc" {
                return url.absoluteString
            }

            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let items = components.queryItems,
                  let uri = items.first(where: { $0.name == "uri" })?.value
            else {
                return nil
            }

            let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased().hasPrefix("wc:") {
                return trimmed
            } else {
                return nil
            }
        }
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
