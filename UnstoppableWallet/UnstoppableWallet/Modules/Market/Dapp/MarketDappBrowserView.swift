import Combine
import Foundation
import SwiftUI
import UIKit
import RxSwift
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

// MARK: - JS 注入自动连接状态管理（简化版）
class MarketDappConnectionObserver: ObservableObject {
    @Published private(set) var connectionState: MarketDappConnectionState = .disconnected
    private let connectInfo: MarketDappBrowserConnectInfo?
    
    init(connectInfo: MarketDappBrowserConnectInfo?, urlHost: String) {
        self.connectInfo = connectInfo
        if connectInfo == nil {
            connectionState = .noAccount
        } else {
            connectionState = .connected
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
    @State private var showReconnectPrompt = true
    
    // DApp 集成管理器
    @StateObject private var dAppManager: DAppIntegrationManager

    init(url: URL, connectInfo: MarketDappBrowserConnectInfo?, onClose: @escaping () -> Void) {
        self.url = url
        self.connectInfo = connectInfo
        self.onClose = onClose

        let chainId = connectInfo?.chainId ?? 1
        let address = connectInfo?.address ?? ""
        _web3Handler = StateObject(wrappedValue: MarketDappWeb3Handler(chainId: chainId, address: address, dAppName: url.host ?? ""))
        _connectionObserver = StateObject(wrappedValue: MarketDappConnectionObserver(connectInfo: connectInfo, urlHost: url.host ?? ""))
        
        // 初始化 DApp 集成管理器（处理 throws）
        // 如果地址无效或为空，使用后备地址（不会实际注入 Provider）
        let safeAddress = address.isEmpty ? "0x0000000000000000000000000000000000000000" : address
        let manager = (try? DAppIntegrationManager(
            chainId: chainId,
            address: safeAddress,
            messageHandler: nil
        )) ?? (try! DAppIntegrationManager(chainId: 1, address: "0x0000000000000000000000000000000000000000"))
        
        _dAppManager = StateObject(wrappedValue: manager)
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
                        dAppManager: connectInfo == nil ? nil : dAppManager,
                        progress: $progress,
                        isLoading: $isLoading
                    )
                    if showReconnectPrompt {
                        ZStack {
                            HighlightedTextView(caution: CautionNew(text: "dapp.reconnect.prompt".localized, type: .warning))
                            HStack {
                                Spacer()
                                Image("close_1_20")
                                    .themeIcon(color: .themeYellow)
                                    .padding(.trailing, .margin8)
                                    .onTapGesture {
                                        showReconnectPrompt = false
                                    }
                            }
                        }
                        .padding(.horizontal, .margin8)
                        .padding(.vertical, .margin8)
                        .transition(.opacity)
                    }
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        NotificationCenter.default.post(name: .init("RefreshDappWebView"), object: nil)
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.themeYellow)
                    }
                    .disabled(isLoading)
                }
            }
            .sheet(item: $web3Handler.destination, onDismiss: {
                web3Handler.handlePresentedDismiss()
            }) { destination in
                if let viewController = destination.viewController {
                    SendEvmConfirmationView(viewController: viewController)
                } else if let swiftUIView = destination.swiftUIView {
                    swiftUIView
                }
            }
        }
    }
}

struct MarketDappWebView: UIViewRepresentable {
    let url: URL
    let connectInfo: MarketDappBrowserConnectInfo?
    let web3Handler: MarketDappWeb3Handler?
    let dAppManager: DAppIntegrationManager?
    @Binding var progress: Double
    @Binding var isLoading: Bool

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(
            onProgress: { progress in
                self.progress = progress
            },
            onLoadingChanged: { isLoading in
                self.isLoading = isLoading
            }
        )
        coordinator.setupRefreshObserver()
        return coordinator
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView: WKWebView
        
        print("[DAppBrowser] INFO: makeUIView called, connectInfo: \(connectInfo != nil ? "YES" : "NO")")
        
        if let connectInfo, let web3Handler, let dAppManager {
            // 使用 DAppIntegrationManager 配置 WebView
            var config = WKWebViewConfiguration()
            config.websiteDataStore = WKWebsiteDataStore.default()
            
            // 设置消息处理器
            print("[DAppBrowser] INFO: Setting messageHandler on dAppManager")
            dAppManager.messageHandler = web3Handler
            
            // 配置 DApp 集成
            print("[DAppBrowser] INFO: Calling dAppManager.configure() for host: \(url.host ?? "unknown")")
            config = dAppManager.configure(webViewConfiguration: config, for: url.host)
            
            webView = WKWebView(frame: .zero, configuration: config)
        } else {
            print("[DAppBrowser] WARNING: No connectInfo/web3Handler/dAppManager, creating plain WebView")
            webView = WKWebView()
        }

        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.bind(webView: webView)
        web3Handler?.bind(webView: webView)
        
        // 触发自动连接
        if dAppManager != nil {
            print("[DAppBrowser] INFO: Setting dAppManager on coordinator")
            context.coordinator.dAppManager = dAppManager
        }
        
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
        private var refreshObserver: NSObjectProtocol?
        private weak var webView: WKWebView?

        // DApp 管理器引用
        weak var dAppManager: DAppIntegrationManager?

        init(onProgress: @escaping (Double) -> Void, onLoadingChanged: @escaping (Bool) -> Void) {
            self.onProgress = onProgress
            self.onLoadingChanged = onLoadingChanged
        }

        deinit {
            if let observer = refreshObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func setupRefreshObserver() {
            refreshObserver = NotificationCenter.default.addObserver(
                forName: .init("RefreshDappWebView"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleRefresh()
            }
        }

        private func handleRefresh() {
            guard let webView = webView else { return }
            webView.reload()
        }

        func bind(webView: WKWebView) {
            self.webView = webView
            progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.onProgress(webView.estimatedProgress)
                }
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            print("[DAppBrowser] INFO: didStartProvisionalNavigation called")
            DispatchQueue.main.async {
                self.onLoadingChanged(true)
                self.onProgress(webView.estimatedProgress)
            }

            // 重置 DApp 连接状态（包括 JavaScript 层）
            print("[DAppBrowser] INFO: Calling dAppManager.reset(in:)")
            dAppManager?.reset(in: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("[DAppBrowser] INFO: didFinish called for URL: \(webView.url?.absoluteString ?? "unknown")")
            DispatchQueue.main.async {
                self.onProgress(1)
                self.onLoadingChanged(false)
            }

            // 触发自动连接（确保在页面加载完成后立即连接）
            print("[DAppBrowser] INFO: Calling triggerAutoConnect")
            dAppManager?.triggerAutoConnect(in: webView) { [weak self] success, error in
                if success {
                    print("[DAppBrowser] INFO: Auto-connect successful ✅")
                } else if let error = error {
                    print("[DAppBrowser] ERROR: Auto-connect failed ❌: \(error.localizedDescription)")
                }
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
            
            // 忽略 wc: 协议的导航，让 DApp 使用 JS 注入的 Provider
            if url.scheme?.lowercased() == "wc" {
                print("[DAppBrowser] Ignoring wc: scheme, using JS injection instead")
                decisionHandler(.cancel)
                return
            }
            
            decisionHandler(.allow)
        }
    }
}
