import Combine
import Foundation
import SwiftUI
import UIKit
import RxSwift
import WalletConnectSign
@preconcurrency import WebKit

struct MarketDappBrowserConnectInfo: Equatable {
    let chainId: Int
    let address: String
}

enum MarketDappConnectionState {
    case connected
    case connecting
    case disconnected
    case noAccount
}

class MarketDappConnectionObserver: ObservableObject {
    @Published private(set) var connectionState: MarketDappConnectionState = .disconnected

    private var disposeBag = DisposeBag()
    private let service: WalletConnectService?
    private let connectInfo: MarketDappBrowserConnectInfo?
    private let urlHost: String

    init(connectInfo: MarketDappBrowserConnectInfo?, urlHost: String) {
        self.connectInfo = connectInfo
        self.urlHost = urlHost

        if connectInfo == nil {
            connectionState = .noAccount
            self.service = nil
            return
        }

        let service = Core.shared.walletConnectSessionManager.service

        self.service = service

        service.sessionsUpdatedObservable
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { [weak self] in
                self?.syncConnectionState()
            })
            .disposed(by: disposeBag)

        syncConnectionState()
    }

    private func syncConnectionState() {
        guard let connectInfo else { return }
        let urlHost = self.urlHost
        let sessions = service?.activeSessions ?? []

        let matchingSession = sessions.first { session in
            let peerUrlString = session.peer.url
            guard let peerUrl = URL(string: peerUrlString),
                  let peerHost = peerUrl.host
            else {
                return false
            }

            let urlMatches = peerHost.lowercased() == urlHost.lowercased() ||
                             urlHost.lowercased().contains(peerHost.lowercased()) ||
                             peerHost.lowercased().contains(urlHost.lowercased())

            let chainMatches = session.chainIds.contains(connectInfo.chainId)

            return urlMatches && chainMatches
        }

        if matchingSession != nil {
            connectionState = .connected
        } else if !sessions.isEmpty {
            connectionState = .disconnected
        } else {
            connectionState = .disconnected
        }
    }
}

struct MarketDappBrowserView: View {
    let url: URL
    let connectInfo: MarketDappBrowserConnectInfo?
    let onClose: () -> Void
    @StateObject private var web3Handler: MarketDappWeb3Handler
    @StateObject private var connectionObserver: MarketDappConnectionObserver
    @State private var progress: Double = 0
    @State private var isLoading = false
    @State private var showConnectionWarning = true

    init(url: URL, connectInfo: MarketDappBrowserConnectInfo?, onClose: @escaping () -> Void) {
        self.url = url
        self.connectInfo = connectInfo
        self.onClose = onClose

        let chainId = connectInfo?.chainId ?? 1
        let address = connectInfo?.address ?? ""
        _web3Handler = StateObject(wrappedValue: MarketDappWeb3Handler(chainId: chainId, address: address, dAppName: url.host ?? ""))
        _connectionObserver = StateObject(wrappedValue: MarketDappConnectionObserver(connectInfo: connectInfo, urlHost: url.host ?? ""))
    }

    @ViewBuilder
    private var connectionStatusView: some View {
        if showConnectionWarning {
            ZStack(alignment: .topTrailing) {
                HighlightedTextView(text: "wallet_connect.no_connection".localized, style: .warning)
                    .padding(.horizontal, .margin16)
                    .padding(.vertical, .margin8)

                Button(action: {
                    showConnectionWarning = false
                }) {
                    Image("close")
//                        .themeIcon(color: .themeYellow)
                        .padding(.margin10)
                }
                .padding(.trailing, .margin8)
            }
        }

/*
        switch connectionObserver.connectionState {
        case .connected:
            EmptyView()
        case .connecting:
            HStack(spacing: .margin8) {
                ProgressView()
                    .tint(.themeYellow)
            }
            .padding(.vertical, .margin8)
            .padding(.horizontal, .margin16)
        case .disconnected:
            HighlightedTextView(text: "wallet_connect.no_connection".localized, style: .warning)
                .padding(.horizontal, .margin16)
                .padding(.vertical, .margin8)
            
        case .noAccount:
            HighlightedTextView(text: "wallet_connect.no_connection".localized, style: .warning)
                .padding(.horizontal, .margin16)
                .padding(.vertical, .margin8)
        }
 */
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
                    
                    connectionStatusView
                }
            }
            .edgesIgnoringSafeArea(.bottom)
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
            let config = WKWebViewConfiguration.make(
                forChainId: connectInfo.chainId,
                address: connectInfo.address,
                messageHandler: web3Handler,
                host: url.host
            )
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
            
            print("[WalletConnect] Navigation action: \(url.absoluteString)")
            print("[WalletConnect] Navigation type: \(navigationAction.navigationType)")

            if let uri = walletConnectUri(url: url) {
                print("[WalletConnect] Detected WalletConnect URI, handling...")
                Task { @MainActor in
                    do {
                        try await Core.shared.appEventHandler.handle(source: .main, event: uri, eventType: .walletConnectUri)
                        print("[WalletConnect] URI handled successfully")
                    } catch {
                        print("[WalletConnect] Error handling URI: \(error)")
                    }
                }
                decisionHandler(.cancel)
                return
            }

            if isMetaMaskExternalUrl(url: url) {
                print("[WalletConnect] MetaMask external navigation blocked: \(url.absoluteString)")
                decisionHandler(.cancel)
                return
            }

            if shouldOpenExternally(url: url) {
                print("[WalletConnect] Opening externally: \(url.absoluteString)")
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

            if isMetaMaskExternalUrl(url: url) {
                print("[WalletConnect] MetaMask external window blocked: \(url.absoluteString)")
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
            let scheme = url.scheme?.lowercased() ?? ""
            let host = url.host?.lowercased() ?? ""
            
            print("[WalletConnect] Checking shouldOpenExternally - scheme: \(scheme), host: \(host)")
            
            // 不拦截 WalletConnect 链接
            if scheme == "wc" {
                print("[WalletConnect] wc: scheme should not open externally, will be handled separately")
                return false
            }
            
            // 非 http/https 协议（除了 about）
            if scheme != "http", scheme != "https" {
                if scheme == "about" {
                    return false
                }
                print("[WalletConnect] Non-http/https scheme, opening externally: \(scheme)")
                return true
            }

            // 特定的外部链接
            if host == "metamask.app.link" || host == "link.walletconnect.com" {
                print("[WalletConnect] Known external host, opening externally: \(host)")
                return true
            }

            return false
        }

        private func isMetaMaskExternalUrl(url: URL) -> Bool {
            let scheme = url.scheme?.lowercased() ?? ""
            let host = url.host?.lowercased() ?? ""
            return scheme == "metamask" || host == "metamask.app.link"
        }

        private func walletConnectUri(url: URL) -> String? {
            let urlString = url.absoluteString
            print("[WalletConnect] Checking URL: \(urlString)")
            
            // 1. 直接 wc: 协议链接
            if url.scheme?.lowercased() == "wc" {
                print("[WalletConnect] Found direct wc: scheme: \(urlString)")
                return urlString
            }
            
            // 2. 从 URL query 参数中提取 uri
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let items = components.queryItems {
                
                // 检查各种可能的参数名
                let possibleParamNames = ["uri", "wc_uri", "walletconnect", "connection", "session"]
                for paramName in possibleParamNames {
                    if let uri = items.first(where: { $0.name.lowercased() == paramName })?.value {
                        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.lowercased().hasPrefix("wc:") {
                            print("[WalletConnect] Found uri in query param '\(paramName)': \(trimmed)")
                            return trimmed
                        }
                    }
                }
            }
            
            // 3. 从 URL fragment 中提取 (hash 部分)
            if let fragment = url.fragment {
                let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.lowercased().hasPrefix("wc:") {
                    print("[WalletConnect] Found uri in fragment: \(trimmed)")
                    return trimmed
                }
            }
            
            // 4. 从 URL path 中提取 (某些 DApp 可能使用 /wc:xxx 格式)
            let path = url.path
            if path.lowercased().contains("wc:") {
                if let range = path.lowercased().range(of: "wc:") {
                    let uri = String(path[range.lowerBound...])
                    print("[WalletConnect] Found uri in path: \(uri)")
                    return uri
                }
            }
            
            // 5. 检查整个 URL 字符串是否包含 wc: 链接
            if urlString.contains("wc:") {
                // 尝试提取 wc: 开头的部分
                if let range = urlString.range(of: "wc:", options: .caseInsensitive) {
                    let uri = String(urlString[range.lowerBound...])
                        .components(separatedBy: .whitespacesAndNewlines)
                        .first ?? String(urlString[range.lowerBound...])
                    print("[WalletConnect] Found uri in full URL: \(uri)")
                    return uri
                }
            }
            
            print("[WalletConnect] No wc: uri found in URL")
            return nil
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
