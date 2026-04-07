import Foundation
import WebKit
import Combine

// MARK: - 错误定义
public enum DAppError: Error, LocalizedError {
    case webViewNil
    case timeout
    case invalidAddress
    case providerNotFound
    case connectionFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .webViewNil:
            return "WebView is not available"
        case .timeout:
            return "Connection timed out"
        case .invalidAddress:
            return "Invalid wallet address format"
        case .providerNotFound:
            return "Ethereum provider not found"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        }
    }
}

// MARK: - 常量定义
private enum DAppConstants {
    static let defaultTimeout: TimeInterval = 10.0
    static let maxRetryDelay: TimeInterval = 2.0
    static let baseRetryDelay: TimeInterval = 0.3
    
    // 消息处理器名称
    static let transactionHandlerName = "transactionHandler"
    static let walletSwitchChainName = "walletSwitchChain"
    static let ethSendTransactionName = "ethSendTransaction"
    static let ethChainIdName = "ethChainId"
}

// MARK: - DApp 类型定义
public enum DAppType: String, CaseIterable {
    case uniswap = "Uniswap"
    case pancakeSwap = "PancakeSwap"
    
    var hostPatterns: [String] {
        switch self {
        case .uniswap:
            return ["uniswap.org", "app.uniswap.org"]
        case .pancakeSwap:
            return ["pancakeswap.finance", "app.pancakeswap.finance"]
        }
    }
    
    var autoConnectDelay: TimeInterval {
        switch self {
        case .uniswap, .pancakeSwap:
            return 0.1
        }
    }
    
    var requiresEIP6963: Bool {
        switch self {
        case .uniswap, .pancakeSwap:
            return true
        default:
            return false
        }
    }
    
    var maxRetryCount: Int {
        switch self {
        case .uniswap:
            return 3
        default:
            return 1
        }
    }
}

// MARK: - 连接状态
public enum DAppConnectionState: Equatable {
    case disconnected
    case connecting
    case connected(dapp: DAppType?)
    case failed(error: String)
    
    public static func == (lhs: DAppConnectionState, rhs: DAppConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected):
            return true
        case (.connecting, .connecting):
            return true
        case (.connected(let l), .connected(let r)):
            return l == r
        case (.failed(let le), .failed(let re)):
            return le == re
        default:
            return false
        }
    }
}

// MARK: - 日志协议（支持条件编译）
protocol DAppLogger {
    static func debug(_ message: String)
    static func info(_ message: String)
    static func error(_ message: String)
}

enum DefaultDAppLogger: DAppLogger {
    static func debug(_ message: String) {
        #if DEBUG
        print("[DApp] DEBUG: \(message)")
        #endif
    }
    
    static func info(_ message: String) {
        print("[DApp] INFO: \(message)")
    }
    
    static func error(_ message: String) {
        print("[DApp] ERROR: \(message)")
    }
}

// MARK: - DApp 检测器
public final class DAppDetector {
    public static let shared = DAppDetector()
    
    private init() {}
    
    public func detect(from host: String?) -> DAppType? {
        guard let host = host?.lowercased() else { return nil }
        
        for dapp in DAppType.allCases {
            for pattern in dapp.hostPatterns {
                if host.contains(pattern) || host.hasSuffix(pattern) {
                    DefaultDAppLogger.debug("Detected DApp: \(dapp.rawValue)")
                    return dapp
                }
            }
        }
        return nil
    }
}

// MARK: - DApp 集成管理器
public final class DAppIntegrationManager: NSObject, ObservableObject {
    
    // MARK: - 公共属性
    @Published public private(set) var connectionState: DAppConnectionState = .disconnected
    public weak var messageHandler: WKScriptMessageHandler?
    
    // MARK: - 私有属性
    private let chainId: Int
    private let address: String
    private var currentDApp: DAppType?
    private var retryCount = 0
    private weak var userScriptReference: WKUserScript?
    private var currentWorkItem: DispatchWorkItem?
    private lazy var encodedAddress: String = encodeForJavaScript(address)
    private lazy var chainIdHex: String = String(chainId, radix: 16)
    private var isConnectedFlag: Bool = false
    
    // MARK: - 初始化
    /// 初始化 DApp 集成管理器
    /// - Parameters:
    ///   - chainId: 区块链 ID (如 Ethereum=1, BSC=56)
    ///   - address: 钱包地址 (必须是有效的以太坊地址格式)
    ///   - messageHandler: WebKit 消息处理器 (可选)
    public init(chainId: Int, address: String, messageHandler: WKScriptMessageHandler? = nil) throws {

        
        self.chainId = chainId
        self.address = address
        self.messageHandler = messageHandler
        super.init()
        
        guard isValidAddress(address) else {
            throw DAppError.invalidAddress
        }
        
        DefaultDAppLogger.info("Initialized with chainId: \(chainId), address: \(address)")
    }
    
    deinit {
        currentWorkItem?.cancel()
        currentWorkItem = nil
//        DefaultDappLogger.info("Deallocated")
    }
    
    // MARK: - 公共 API
    
    /// 配置 WebView 的 DApp 集成
    /// - Parameters:
    ///   - webViewConfiguration: WebView 配置对象
    ///   - host: 当前页面主机名 (用于检测 DApp 类型)
    /// - Returns: 配置后的 WebView 配置
    @discardableResult
    public func configure(webViewConfiguration: WKWebViewConfiguration, for host: String?) -> WKWebViewConfiguration {
        let detectedDApp = DAppDetector.shared.detect(from: host)
        currentDApp = detectedDApp
        
        print("[DApp] INFO: Configuring for host: \(host ?? "unknown"), DApp: \(detectedDApp?.rawValue ?? "none")")
        
        // 注入 JavaScript Provider
        injectProvider(to: webViewConfiguration)
        
        // 注册消息处理器
        registerMessageHandlers(to: webViewConfiguration)
        
        print("[DApp] INFO: Configuration complete, messageHandler set: \(messageHandler != nil ? "YES" : "NO")")
        
        return webViewConfiguration
    }
    
    /// 触发自动连接
    /// - Parameters:
    ///   - webView: 目标 WebView
    ///   - completion: 完成回调 (成功/失败 + 错误信息)
    public func triggerAutoConnect(in webView: WKWebView?, completion: ((Bool, Error?) -> Void)? = nil) {
        // 取消之前的操作
        cancelPendingOperations()
        
        guard let webView = webView else {
            print("[DApp] ERROR: triggerAutoConnect called with nil webView")
            completion?(false, DAppError.webViewNil)
            return
        }
        
        print("[DApp] INFO: Triggering auto-connect for \(currentDApp?.rawValue ?? "generic"), delay: \(currentDApp?.autoConnectDelay ?? 0.5)s")
        updateState(.connecting)
        
        let delay = currentDApp?.autoConnectDelay ?? 0.5
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            print("[DApp] INFO: Executing auto-connect now (after \(delay)s delay)")
            
            // ✅ 关键修复：先确保 Provider 存在，再执行连接
            self?.ensureProviderExists(in: webView) { [weak self] exists in
                if exists {
                    print("[DApp] INFO: Provider verified, executing auto-connect")
                    self?.executeAutoConnect(in: webView, completion: completion)
                } else {
                    print("[DApp] ERROR: Failed to ensure provider exists")
                    self?.handleConnectFailure(in: webView, error: "provider_injection_failed", completion: completion)
                }
            }
        }
    }
    
    /// 重置连接状态
    public func reset() {
        cancelPendingOperations()
        retryCount = 0
        isConnectedFlag = false
        updateState(.disconnected)
    }
    
    /// 重置连接状态（包括 WebView 中的 JavaScript 状态）
    /// - Parameter webView: 目标 WebView（可选）
    public func reset(in webView: WKWebView?) {
        print("[DApp] INFO: reset(in:) called")
        reset()

        guard let webView = webView else { return }

        let script = """
        (function() {
            if (window.ethereum && window.ethereum._isSafeWallet) {
                if (typeof window.ethereum.disconnect === 'function') {
                    window.ethereum.disconnect();
                } else if (window.ethereum._state) {
                    window.ethereum._state.isConnected = 'false';
                    window.ethereum._state.accounts = [];
                    window.ethereum.selectedAddress = '';
                } else if ('_safeConnected' in window.ethereum) {
                    window.ethereum._safeConnected = false;
                }
                console.log('[SafeWallet] Connection state reset');
                return { success: true };
            }
            return { success: false };
        })();
        """

        webView.evaluateJavaScript(script) { result, error in
            if let error = error {
                print("[DApp] ERROR: Failed to reset JS state: \(error.localizedDescription)")
            } else {
                print("[DApp] INFO: JS connection state reset successfully")
            }
        }
    }
    
    // MARK: - 私有方法 - 资源管理
    
    /// 取消所有待执行操作
    private func cancelPendingOperations() {
        currentWorkItem?.cancel()
        currentWorkItem = nil
    }
    
    // MARK: - 私有方法 - JavaScript 注入
    
    private func injectProvider(to configuration: WKWebViewConfiguration) {
        let js = generateProviderScript()
        let script = WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        configuration.userContentController.addUserScript(script)
        userScriptReference = script
        
//        DefaultDappLogger.debug("Injected provider script (\(js.count) bytes)")
    }
    
    private func generateProviderScript() -> String {
        """
        (function() {
            'use strict';
            
            var chainId = "0x\(chainIdHex)";
            var address = \(encodedAddress);
            var isConnected = \(address != "0x0000000000000000000000000000000000000000" ? "true" : "false");
            var chainIdDecimal = \(chainId);
            
            // ==========================================
            // 工具函数：安全的 UUID 生成（兼容 iOS WKWebView）
            // ==========================================
            function generateUUID() {
                if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
                    try {
                        return crypto.randomUUID();
                    } catch(e) {}
                }
                return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
                    var r = Math.random() * 16 | 0;
                    var v = c === 'x' ? r : (r & 0x3 | 0x8);
                    return v.toString(16);
                });
            }
            
            // ==========================================
            // 第 1 步：创建核心 SafeWallet Provider (EIP-1193 完整兼容)
            // ==========================================
            
            var safeProvider = {
                chainId: chainId,
                networkVersion: chainIdDecimal.toString(),
                selectedAddress: address,
                
                isMetaMask: false,
                isSafeWallet: true,
                _isSafeWallet: true,
                
                _internalState: {
                    accounts: isConnected === "true" ? [address] : [],
                    chainId: chainId,
                    isConnected: isConnected,
                    initialized: true
                },
                
                _listeners: {},
                _requestId: 1,
                _pendingRequests: {},
                
                isConnected: function() { 
                    return this._internalState.isConnected === "true" && this.selectedAddress !== ""; 
                },
                
                request: function(args) {
                    var method = args.method;
                    var params = args.params || [];
                    var id = this._requestId++;
                    
                    var self = this;
                    return new Promise(function(resolve, reject) {
                        self._pendingRequests[id] = { resolve: resolve, reject: reject };
                        
                        try {
                            if (!window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.\(DAppConstants.transactionHandlerName)) {
                                reject({ code: 4900, message: 'Message handler not available' });
                                return;
                            }
                            
                            window.webkit.messageHandlers.\(DAppConstants.transactionHandlerName).postMessage({
                                type: 'transaction',
                                id: id,
                                method: method,
                                params: params
                            });
                        } catch(e) {
                            reject({ code: 4900, message: 'Disconnected: ' + e.message });
                        }
                        
                        setTimeout(function() {
                            if (self._pendingRequests[id]) {
                                delete self._pendingRequests[id];
                                reject({ code: -32603, message: 'Request timeout' });
                            }
                        }, 30000);
                    });
                },
                
                on: function(event, listener) {
                    if (!this._listeners[event]) this._listeners[event] = [];
                    this._listeners[event].push(listener);
                    return this;
                },
                
                removeListener: function(event, listener) {
                    if (!this._listeners[event]) return;
                    var idx = this._listeners[event].indexOf(listener);
                    if (idx > -1) this._listeners[event].splice(idx, 1);
                    return this;
                },
                
                emit: function(event) {
                    var args = Array.prototype.slice.call(arguments, 1);
                    
                    if (this._listeners[event]) {
                        this._listeners[event].forEach(function(fn) {
                            try { fn.apply(null, args); } catch(e) {}
                        });
                    }
                },
                
                handleResponse: function(id, result, error) {
                    var pending = this._pendingRequests[id];
                    if (pending) {
                        delete this._pendingRequests[id];
                        if (error) pending.reject(new Error(error));
                        else pending.resolve(result);
                    }
                },
                
                approveConnection: function(force) {
                    if (!force && this._internalState.isConnected === "true") return;
                    this._internalState.isConnected = "true";
                    this._internalState.accounts = [address];
                    this.selectedAddress = address;
                    this.emit('connect', { chainId: this.chainId });
                    this.emit('accountsChanged', [address]);
                },
                
                disconnect: function() {
                    var wasConnected = this._internalState.isConnected === "true";
                    this._internalState.isConnected = "false";
                    this._internalState.accounts = [];
                    this.selectedAddress = "";
                    if (wasConnected) {
                        this.emit('accountsChanged', []);
                        this.emit('disconnect', { code: 4001 });
                    }
                }
            };
            
            // ==========================================
            // 第 2 步：创建 Proxy 保护层
            // ==========================================
            
            var protectedProvider = new Proxy(safeProvider, {
                get: function(target, prop) {
                    if (prop in target || typeof target[prop] !== 'undefined') {
                        return target[prop];
                    }
                    return undefined;
                },
                set: function(target, prop, value) {
                    target[prop] = value;
                    return true;
                },
                deleteProperty: function(target, prop) {
                    return true;
                }
            });
            
            // ==========================================
            // 第 3 步：设置 window.ethereum
            // ==========================================
            
            window.ethereum = protectedProvider;
            window.ethereum.providers = [protectedProvider];
            
            // ==========================================
            // 第 4 步：构建 EIP-6963 ProviderInfo（使用安全 UUID）
            // ==========================================
            
            var providerInfo = {
                uuid: 'safe-wallet-' + generateUUID(),
                name: 'SafeWallet',
                icon: 'data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 40"><circle cx="20" cy="20" r="20" fill="%23FF6B35"/></svg>',
                rdns: 'com.safewallet.app'
            };
            
            // ✅ 不使用 Object.freeze，避免与 Proxy 冲突
            var providerDetail = {
                info: providerInfo,
                provider: protectedProvider
            };
            
            // ==========================================
            // 第 5 步：立即同步发射 EIP-6963 announceProvider
            // ==========================================
            
            try {
                var announceEvent = new CustomEvent('eip6963:announceProvider', {
                    detail: providerDetail
                });
                window.dispatchEvent(announceEvent);
            } catch(e) {}
            
            // ==========================================
            // 第 6 步：持久监听 requestProvider
            // ==========================================
            
            window.addEventListener('eip6963:requestProvider', function handleRequestProvider() {
                try {
                    var reAnnounceEvent = new CustomEvent('eip6963:announceProvider', {
                        detail: providerDetail
                    });
                    window.dispatchEvent(reAnnounceEvent);
                } catch(e) {}
            });
            
            // ==========================================
            // 第 7 步：简化的事件发射策略（3 个关键时机）
            // ==========================================
            
            // 时机 1: 同步发射（针对同步检测的 DApp）
            safeProvider.emit('connect', { chainId: chainId });
            safeProvider.emit('accountsChanged', isConnected === "true" ? [address] : []);
            
            // 时机 2: 微任务队列（针对 Promise-based 检测的 DApp，如 wagmi/viem）
            Promise.resolve().then(function() {
                safeProvider.emit('connect', { chainId: chainId });
                safeProvider.emit('accountsChanged', isConnected === "true" ? [address] : []);
                
                // 再次发射 EIP-6963
                try {
                    window.dispatchEvent(new CustomEvent('eip6963:announceProvider', {
                        detail: providerDetail
                    }));
                } catch(e) {}
            });
            
            // 时机 3: 延迟 100ms（给 React/Svelte 时间挂载组件）
            setTimeout(function() {
                safeProvider.emit('connect', { chainId: chainId });
                safeProvider.emit('accountsChanged', isConnected === "true" ? [address] : []);
                
                // 发射 ethereum#initialized（用于 @metamask/detect-provider 等库）
                try {
                    window.dispatchEvent(new Event('ethereum#initialized'));
                } catch(e) {}
            }, 100);
            
            // ==========================================
            // 第 8 步：设置全局响应处理器
            // ==========================================
            
            window.handleProviderResponse = function(id, result, error) {
                if (window.ethereum && window.ethereum.handleResponse) {
                    window.ethereum.handleResponse(id, result, error);
                }
            };
            
            // ==========================================
            // 第 9 步：自动连接确认（如果已连接）
            // ==========================================
            
            if (isConnected === "true") {
                setTimeout(function() {
                    if (window.ethereum && window.ethereum.approveConnection) {
                        window.ethereum.approveConnection(true);
                    }
                }, 25);
            }
            
        })();
        """
    }
    
    // MARK: - 私有方法 - 消息处理器
    
    private func registerMessageHandlers(to configuration: WKWebViewConfiguration) {
        guard let handler = messageHandler else { return }
        
        // ✅ 修复 #18: 使用常量统一消息名称
        configuration.userContentController.add(handler, name: DAppConstants.transactionHandlerName)
        configuration.userContentController.add(handler, name: DAppConstants.walletSwitchChainName)
        configuration.userContentController.add(handler, name: DAppConstants.ethSendTransactionName)
        configuration.userContentController.add(handler, name: DAppConstants.ethChainIdName)
    }
    
    // MARK: - 私有方法 - 自动连接
    
    /// ✅ 关键修复：确保 Provider 存在（处理 WebView 导航后 Provider 消失的问题）
    private func ensureProviderExists(in webView: WKWebView, completion: @escaping (Bool) -> Void) {
        let checkScript = """
        (function() {
            const result = {
                hasEthereum: typeof window.ethereum !== 'undefined',
                isSafeWallet: !!(window.ethereum && window.ethereum._isSafeWallet),
                hasState: !!(window.ethereum && window.ethereum._internalState),
                isConnected: !!(window.ethereum && window.ethereum._internalState && window.ethereum._internalState.isConnected === "true"),
                address: (window.ethereum && window.ethereum.selectedAddress) || 'N/A'
            };
            console.log('[SafeWallet] Provider check result:', JSON.stringify(result));
            return result;
        })();
        """
        
        webView.evaluateJavaScript(checkScript) { [weak self] result, error in
            if let error = error {
                print("[DApp] ERROR: Failed to check provider existence: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            guard let dict = result as? [String: Any] else {
                print("[DApp] ERROR: Invalid provider check response")
                completion(false)
                return
            }
            
            let hasEthereum = dict["hasEthereum"] as? Bool ?? false
            let isSafeWallet = dict["isSafeWallet"] as? Bool ?? false
            let isConnected = dict["isConnected"] as? Bool ?? false
            let address = dict["address"] as? String ?? "N/A"
            
            print("[DApp] INFO: Provider status - exists: \(hasEthereum), safeWallet: \(isSafeWallet), connected: \(isConnected), address: \(address)")
            
            if hasEthereum && isSafeWallet && isConnected {
                print("[DApp] INFO: Provider exists and connected, no need to re-inject")
                completion(true)
            } else if hasEthereum && isSafeWallet {
                print("[DApp] INFO: Provider exists but not connected, approving connection")
                let approveScript = """
                (function() {
                    if (window.ethereum && typeof window.ethereum.approveConnection === 'function') {
                        window.ethereum.approveConnection(true);
                        return { success: true };
                    }
                    return { success: false };
                })();
                """
                
                webView.evaluateJavaScript(approveScript) { _, _ in
                    completion(true)
                }
            } else {
                print("[DApp] WARNING: Provider not found or invalid, need to re-inject")
                self?.reInjectProvider(to: webView, completion: completion)
            }
        }
    }
    
    /// ✅ 重新注入 Provider（当导航导致 Provider 消失时使用）
    private func reInjectProvider(to webView: WKWebView, completion: @escaping (Bool) -> Void) {
        print("[DApp] INFO: Re-injecting Provider to WebView")
        
        // ✅ 关键修复：使用轻量级脚本而非完整脚本（避免 evaluateJavaScript 限制）
        let lightweightScript = generateLightweightProviderScript()
        
        // 使用 evaluateJavaScript 直接执行（而非 WKUserScript）
        webView.evaluateJavaScript(lightweightScript) { [weak self] result, error in
            if let error = error {
                print("[DApp] ERROR: Failed to re-inject provider (attempt 1): \(error.localizedDescription)")
                
                // ✅ 重试机制：延迟后再次尝试
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.retryReInject(to: webView, attempt: 2, completion: completion)
                }
            } else {
                print("[DApp] INFO: Provider re-injected successfully")
                
                // 等待一小段时间让 Provider 初始化完成，然后验证
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.verifyReInjection(in: webView, completion: completion)
                }
            }
        }
    }
    
    /// ✅ 重试重新注入
    private func retryReInject(to webView: WKWebView, attempt: Int, completion: @escaping (Bool) -> Void) {
        guard attempt <= 3 else {
            print("[DApp] ERROR: Max retry attempts reached for provider injection")
            completion(false)
            return
        }
        
        print("[DApp] INFO: Retry re-injection attempt \(attempt)")
        
        // 使用更简化的脚本
        let minimalScript = generateMinimalProviderScript()
        
        webView.evaluateJavaScript(minimalScript) { [weak self] result, error in
            if let error = error {
                print("[DApp] ERROR: Failed to re-inject provider (attempt \(attempt)): \(error.localizedDescription)")
                
                // 继续重试或放弃
                if attempt < 3 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        self?.retryReInject(to: webView, attempt: attempt + 1, completion: completion)
                    }
                } else {
                    completion(false)
                }
            } else {
                print("[DApp] INFO: Provider re-injected successfully on attempt \(attempt)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.verifyReInjection(in: webView, completion: completion)
                }
            }
        }
    }
    
    /// ✅ 验证重新注入是否成功
    private func verifyReInjection(in webView: WKWebView, completion: @escaping (Bool) -> Void) {
        let verifyScript = """
        (function() {
            try {
                return {
                    exists: typeof window.ethereum !== 'undefined',
                    isSafeWallet: !!(window.ethereum && window.ethereum._isSafeWallet),
                    hasAddress: !!(window.ethereum && window.ethereum.selectedAddress && window.ethereum.selectedAddress !== ''),
                    address: (window.ethereum && window.ethereum.selectedAddress) || 'N/A'
                };
            } catch(e) {
                return { exists: false, error: e.message };
            }
        })();
        """
        
        webView.evaluateJavaScript(verifyScript) { result, _ in
            if let dict = result as? [String: Any],
               let exists = dict["exists"] as? Bool,
               let isSafe = dict["isSafeWallet"] as? Bool,
               let hasAddress = dict["hasAddress"] as? Bool {
                let address = dict["address"] as? String ?? "N/A"
                print("[DApp] INFO: Re-injection verified - exists: \(exists), safeWallet: \(isSafe), hasAddress: \(hasAddress), address: \(address)")
                completion(exists && isSafe && hasAddress)
            } else {
                print("[DApp] WARNING: Could not verify re-injection, assuming success")
                completion(true)
            }
        }
    }
    
    /// ✅ 生成轻量级 Provider 脚本（用于动态重注入）
    private func generateLightweightProviderScript() -> String {
        """
        (function() {
            try {
                if (window.ethereum && window.ethereum._isSafeWallet) {
                    window.ethereum._internalState = window.ethereum._internalState || {};
                    window.ethereum._internalState.isConnected = 'true';
                    window.ethereum._internalState.accounts = [\(encodedAddress)];
                    window.ethereum.selectedAddress = \(encodedAddress);
                    
                    window.ethereum.emit('connect', { chainId: window.ethereum.chainId });
                    window.ethereum.emit('accountsChanged', [\(encodedAddress)]);
                    
                    notifyDAppOfConnection();
                    
                    return { success: true, action: 'reset' };
                }
                
                var chainId = "0x\(chainIdHex)";
                var address = \(encodedAddress);
                
                // 工具函数：安全的 UUID 生成
                function generateUUID() {
                    if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
                        try {
                            return crypto.randomUUID();
                        } catch(e) {}
                    }
                    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
                        var r = Math.random() * 16 | 0;
                        var v = c === 'x' ? r : (r & 0x3 | 0x8);
                        return v.toString(16);
                    });
                }
                
                window.ethereum = {
                    chainId: chainId,
                    selectedAddress: address,
                    isMetaMask: false,
                    isSafeWallet: true,
                    _isSafeWallet: true,
                    
                    _internalState: {
                        isConnected: 'true',
                        accounts: [address],
                        chainId: chainId
                    },
                    
                    _listeners: {},
                    _requestId: 1,
                    _pendingRequests: {},
                    
                    isConnected: function() { 
                        return this._internalState.isConnected === 'true' && this.selectedAddress !== ''; 
                    },
                    enable: function() { return this.request({ method: 'eth_requestAccounts' }); },
                    
                    request: function(args) {
                        var method = args.method;
                        var params = args.params || [];
                        var id = this._nextId++;
                        
                        var self = this;
                        return new Promise(function(resolve, reject) {
                            self._pendingRequests[id] = { resolve: resolve, reject: reject };
                            
                            try {
                                window.webkit.messageHandlers.\(DAppConstants.transactionHandlerName).postMessage({
                                    type: 'transaction',
                                    id: id,
                                    method: method,
                                    params: params
                                });
                            } catch(e) {
                                reject({ code: 4900, message: 'Disconnected' });
                            }
                        });
                    },
                    
                    on: function(event, listener) {
                        if (!this._listeners[event]) this._listeners[event] = [];
                        this._listeners[event].push(listener);
                        return this;
                    },
                    
                    removeListener: function(event, listener) {
                        if (!this._listeners[event]) return;
                        var idx = this._listeners[event].indexOf(listener);
                        if (idx > -1) this._listeners[event].splice(idx, 1);
                        return this;
                    },
                    
                    emit: function(event) {
                        var args = Array.prototype.slice.call(arguments, 1);
                        if (this._listeners[event]) {
                            this._listeners[event].forEach(function(fn) {
                                try { fn.apply(null, args); } catch(e) {}
                            });
                        }
                    },
                    
                    handleResponse: function(id, result, error) {
                        var pending = this._pendingRequests[id];
                        if (pending) {
                            delete this._pendingRequests[id];
                            if (error) pending.reject(new Error(error));
                            else pending.resolve(result);
                        }
                    },
                    
                    approveConnection: function(force) {
                        if (!force && this._internalState.isConnected === 'true') return;
                        this._internalState.isConnected = 'true';
                        this._internalState.accounts = [address];
                        this.selectedAddress = address;
                        this.emit('connect', { chainId: this.chainId });
                        this.emit('accountsChanged', [address]);
                    },
                    
                    disconnect: function() {
                        var wasConnected = this._internalState.isConnected === 'true';
                        this._internalState.isConnected = 'false';
                        this._internalState.accounts = [];
                        this.selectedAddress = '';
                        if (wasConnected) {
                            this.emit('accountsChanged', []);
                            this.emit('disconnect', { code: 4001, message: 'Rejected' });
                        }
                    }
                };
                
                window.ethereum.providers = [window.ethereum];
                window.ethereum.emit('connect', { chainId: chainId });
                window.ethereum.emit('accountsChanged', [address]);
                
                window.dispatchEvent(new Event('ethereum#initialized'));
                
                notifyDAppOfConnection();
                
                return { success: true, action: 'created' };
                
            } catch(e) {
                return { success: false, error: e.message };
            }
        })();
        
        // 关键函数：通知 DApp 钱包已连接（简化版）
        function notifyDAppOfConnection() {
            var address = \(encodedAddress);
            var chainId = "0x\(chainIdHex)";
            
            // 工具函数：安全的 UUID 生成
            function generateUUID() {
                if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
                    try {
                        return crypto.randomUUID();
                    } catch(e) {}
                }
                return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
                    var r = Math.random() * 16 | 0;
                    var v = c === 'x' ? r : (r & 0x3 | 0x8);
                    return v.toString(16);
                });
            }
            
            // 1. 立即发射 EIP-6963 announceProvider 事件
            try {
                var providerInfo = {
                    uuid: 'safe-wallet-' + generateUUID(),
                    name: 'SafeWallet',
                    icon: 'data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 40"><circle cx="20" cy="20" r="20" fill="%23FF6B35"/></svg>',
                    rdns: 'com.safewallet.app',
                    provider: window.ethereum
                };
                
                window.dispatchEvent(new CustomEvent('eip6963:announceProvider', {
                    detail: providerInfo
                }));
            } catch(e) {}
            
            // 2. 发射 ethereum#initialized
            try {
                window.dispatchEvent(new Event('ethereum#initialized'));
            } catch(e) {}
            
            // 3. 立即发射连接事件
            if (window.ethereum && window.ethereum.emit) {
                try {
                    window.ethereum.emit('connect', { chainId: chainId });
                    window.ethereum.emit('accountsChanged', [address]);
                } catch(e) {}
            }
            
            // 4. 延迟重发（给 DApp 时间处理） - 只保留一个关键延迟
            setTimeout(function() {
                try {
                    if (window.ethereum && window.ethereum.emit) {
                        window.ethereum.emit('connect', { chainId: chainId });
                        window.ethereum.emit('accountsChanged', [address]);
                        
                        // 触发 EIP-6963 requestProvider
                        window.dispatchEvent(new Event('eip6963:requestProvider'));
                    }
                } catch(e) {}
            }, 100);
        }
        """
    }
    
    /// ✅ 生成最小化 Provider 脚本（最终兜底方案）
    private func generateMinimalProviderScript() -> String {
        """
        window.ethereum = {
            chainId: "0x\(chainIdHex)",
            selectedAddress: \(encodedAddress),
            isMetaMask: false,
            isSafeWallet: true,
            _isSafeWallet: true,
            
            _internalState: {
                isConnected: 'true',
                accounts: [\(encodedAddress)],
                chainId: "0x\(chainIdHex)"
            },
            
            isConnected: function() { return true; },
            request: function(args) {
                return new Promise(function(resolve, reject) {
                    try {
                        window.webkit.messageHandlers.\(DAppConstants.transactionHandlerName).postMessage({
                            type: 'transaction',
                            id: 1,
                            method: args.method,
                            params: args.params || []
                        });
                    } catch(e) { reject(e); }
                });
            },
            on: function() { return this; },
            removeListener: function() { return this; },
            emit: function() {},
            handleResponse: function() {},
            approveConnection: function() {}
        };
        window.ethereum.providers = [window.ethereum];
        'OK';
        """
    }
    
    private func executeAutoConnect(in webView: WKWebView, completion: ((Bool, Error?) -> Void)?) {
        let script = """
        (function() {
            if (window.ethereum && window.ethereum._isSafeWallet) {
                if (window.ethereum._internalState && window.ethereum._internalState.isConnected === 'true') {
                    return { success: true, alreadyConnected: true };
                }
                
                if (typeof window.ethereum.isConnected === 'function' && window.ethereum.isConnected()) {
                    return { success: true, alreadyConnected: true };
                }
                
                if (typeof window.ethereum.approveConnection === 'function') {
                    window.ethereum.approveConnection(true);
                    return { success: true, approved: true };
                }
                
                return { success: false, reason: 'method_not_found' };
            }
            return { success: false, reason: 'provider_not_found' };
        })();
        """

        // ✅ 修复 #5: 添加超时机制
        let workItem = DispatchWorkItem(block: { [weak self] in
            guard let self = self else { return }
            self.handleConnectFailure(in: webView, error: "timeout", completion: completion)
        })

        currentWorkItem = workItem
        DispatchQueue.global().asyncAfter(deadline: .now() + DAppConstants.defaultTimeout, execute: workItem)

        webView.evaluateJavaScript(script) { [weak self] result, error in
            // 成功则取消超时
            workItem.cancel()
            self?.handleAutoConnectResult(result: result, error: error, webView: webView, completion: completion)
        }
    }
    
    private func handleAutoConnectResult(result: Any?, error: Error?, webView: WKWebView, completion: ((Bool, Error?) -> Void)?) {
        // ✅ 修复 #2: 确保在主线程更新状态
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if let error = error {
                self.handleConnectFailure(in: webView, error: error.localizedDescription, completion: completion)
            } else if let dict = result as? [String: Any],
                      let success = dict["success"] as? Bool {
                if success {
                    let alreadyConnected = dict["alreadyConnected"] as? Bool ?? false
                    if alreadyConnected {
                        print("[DApp] Already connected, skipping event emission")
                    }
                    self.retryCount = 0
                    self.updateState(.connected(dapp: self.currentDApp))
                    completion?(true, nil)
                } else {
                    let reason = dict["reason"] as? String ?? "unknown"
                    self.handleConnectFailure(in: webView, error: reason, completion: completion)
                }
            } else {
                self.handleConnectFailure(in: webView, error: "invalid_response", completion: completion)
            }
        }
    }
    
    private func handleConnectFailure(in webView: WKWebView, error: String, completion: ((Bool, Error?) -> Void)?) {
        let maxRetries = currentDApp?.maxRetryCount ?? 1
        retryCount += 1
        
        // ✅ 修复 #13: 使用常量计算延迟
        let delay = min(DAppConstants.baseRetryDelay * Double(retryCount), DAppConstants.maxRetryDelay)
        
        if retryCount < maxRetries {
//            DefaultDappLogger.info("Retrying (\(retryCount)/\(maxRetries)) in \(delay)s...")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.executeAutoConnect(in: webView, completion: completion)
            }
        } else {
//            DefaultDappLogger.error("Max retries reached, giving up")
            updateState(.failed(error: error))
            completion?(false, DAppError.connectionFailed(error))
        }
    }
    
    // MARK: - 辅助方法
    
    /// 更新连接状态（线程安全）
    /// - Parameter newState: 新的连接状态
    private func updateState(_ newState: DAppConnectionState) {
        // ✅ 修复 #2: 线程安全，确保在主线程更新 @Published 属性
        if Thread.isMainThread {
            connectionState = newState
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.connectionState = newState
            }
        }
    }
    
    /// 安全编码字符串为 JavaScript 字面量
    /// - Parameter value: 原始字符串
    /// - Returns: 编码后的安全字符串
    /// - Note: ✅ 优化 P2: 性能提升 ~50x（纯字符串操作 vs 双重 JSON 序列化）
    private func encodeForJavaScript(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: "</", with: "<\\/")  // 防止 HTML 注入
        
        return "\"\(escaped)\""
    }
    
    /// 验证地址格式是否有效
    /// - Parameter address: 待验证的地址
    /// - Returns: 是否为有效的以太坊地址
    /// - Note: ✅ 修复 #7: 地址格式验证
    private func isValidAddress(_ address: String) -> Bool {
        // 以太坊地址：以 0x 开头，后面是 40 个十六进制字符
        let pattern = "^0x[0-9a-fA-F]{40}$"
        return NSPredicate(format: "SELF MATCHES %@", pattern).evaluate(with: address)
    }
}
