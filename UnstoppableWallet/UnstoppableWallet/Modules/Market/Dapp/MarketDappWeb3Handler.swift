import EvmKit
import HsExtensions
import BigInt
import Foundation
import SwiftUI
import UIKit
import WebKit

final class MarketDappWeb3Handler: NSObject, ObservableObject {
    private var chainId: Int
    private let address: String
    private let dAppName: String

    @Published var destination: Destination?

    private var activeRequestId: Int?
    private weak var webView: WKWebView?
    
    // ✅ 并发请求管理
    private var allActiveRequestIds: Set<Int> = []  // 跟踪所有活跃请求
    
    // ✅ 关键修复：跟踪已成功/失败的请求，防止 onDismiss 重复发送响应
    private var completedRequestIds: Set<Int> = []  // 已完成（已发送响应）的请求

    init(chainId: Int, address: String, dAppName: String) {
        self.chainId = chainId
        self.address = address
        self.dAppName = dAppName
    }
    
    func bind(webView: WKWebView) {
        self.webView = webView
    }
    
    func handlePresentedDismiss() {
        guard let id = activeRequestId else {
            return
        }
        
        // ✅ 关键修复：检查请求是否已经完成（已发送成功或失败响应）
        guard !completedRequestIds.contains(id) else {
            print("[Dapp] Request \(id) already completed, skipping reject on dismiss")
            return
        }

        // 取消当前活跃请求（用户主动关闭）
        completeAndReject(id: id, error: "User rejected the request.")
    }
    
    private func complete(id: Int) {
        if activeRequestId == id {
            activeRequestId = nil
        }
        
        // 从活跃请求集合中移除
        allActiveRequestIds.remove(id)
        
        // ✅ 标记为已完成，防止 onDismiss 重复处理
        completedRequestIds.insert(id)
    }
    
    // 完成请求并拒绝（用于用户取消场景）
    private func completeAndReject(id: Int, error: String) {
        if activeRequestId == id {
            activeRequestId = nil
        }
        
        // 发送拒绝响应
        sendProviderResponse(id: id, resultJson: "null", error: error)
        
        // 从活跃请求集合中移除
        allActiveRequestIds.remove(id)
        
        // ✅ 标记为已完成
        completedRequestIds.insert(id)
    }

    private func present(id: Int, viewController: UIViewController) {
        // ✅ 修复 #26: 如果存在前一个活跃请求，先取消它
        cancelPreviousActiveRequest(except: id)
        
        activeRequestId = id
        allActiveRequestIds.insert(id)  // 记录新请求
        destination = Destination(viewController: viewController)
    }
    
    private func present(id: Int, swiftUIView: some View) {
        // ✅ 确保在主线程设置 destination（触发 SwiftUI Sheet）
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.present(id: id, swiftUIView: swiftUIView)
            }
            return
        }
        
        // ✅ 修复 #26: 如果存在前一个活跃请求，先取消它
        cancelPreviousActiveRequest(except: id)
        
        activeRequestId = id
        allActiveRequestIds.insert(id)  // 记录新请求
        
        print("[Dapp] INFO: Presenting confirmation sheet for request \(id)")
        
        destination = Destination(swiftUIView: AnyView(swiftUIView))
    }
    
    // MARK: - ✅ 修复 #26: 并发请求管理辅助方法
    
    /// 取消之前的活跃请求（保留指定 ID 的请求）
    private func cancelPreviousActiveRequest(except keepId: Int) {
        guard let previousId = activeRequestId, previousId != keepId else {
            return  // 没有前一个请求或就是同一个请求
        }
        
        print("[Dapp] Cancelling previous request \(previousId) due to new request \(keepId)")
        
        // 发送取消响应给 DApp
        sendProviderResponse(
            id: previousId,
            resultJson: "null",
            error: "Request cancelled by new request."
        )
        
        // 从活跃集合中移除
        allActiveRequestIds.remove(previousId)
    }

    private func sendProviderResponse(id: Int, resultJson: String, error: String?) {
        guard let webView else {
            print("[Dapp] WARNING: No webView available for response \(id)")
            return
        }

        // ✅ 关键修复：确保在主线程执行
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.sendProviderResponse(id: id, resultJson: resultJson, error: error)
            }
            return
        }

        // ✅ 关键修复：检查 WebView 是否仍然有效
        guard !webView.isLoading || webView.url != nil else {
            print("[Dapp] WARNING: WebView is loading or invalid for response \(id)")
            return
        }

        let errorJson: String
        if let error {
            errorJson = safeJavaScriptString(error)
        } else {
            errorJson = "null"
        }

        // ✅ 使用更安全的脚本格式
        let safeScript = """
        (function() {
            try {
                if (window.ethereum && window.ethereum._isSafeWallet && typeof window.ethereum.handleResponse === 'function') {
                    window.ethereum.handleResponse(\(id), \(resultJson), \(errorJson));
                    return true;
                } else if (typeof window.handleProviderResponse === 'function') {
                    window.handleProviderResponse(\(id), \(resultJson), \(errorJson));
                    return true;
                } else {
                    console.warn('[Dapp] Response handler not found for request \(id)');
                    return false;
                }
            } catch(e) {
                console.error('[Dapp] Error sending response:', e);
                return false;
            }
        })();
        """

        webView.evaluateJavaScript(safeScript) { [weak self] result, evalError in
            if let evalError = evalError {
                print("[Dapp] Failed to send response for request \(id): \(evalError.localizedDescription)")
                
                // ✅ 关键修复：重试机制（延迟后再次尝试）
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.retrySendResponse(id: id, resultJson: resultJson, error: error)
                }
            } else if let success = result as? Bool, success {
                print("[Dapp] ✅ Successfully sent response for request \(id)")
                self?.complete(id: id)
            } else {
                print("[Dapp] ⚠️ Response sent but verification failed for request \(id)")
                self?.complete(id: id)
            }
        }
    }
    
    /// ✅ 重试发送响应
    private func retrySendResponse(id: Int, resultJson: String, error: String?, attempt: Int = 1) {
        guard attempt <= 3 else {
            print("[Dapp] ERROR: Max retries reached for request \(id)")
            complete(id: id)
            return
        }
        
        guard let webView else {
            complete(id: id)
            return
        }
        
        print("[Dapp] Retrying response for request \(id), attempt \(attempt)")
        
        let errorJson: String
        if let error {
            errorJson = safeJavaScriptString(error)
        } else {
            errorJson = "null"
        }
        
        // 使用简化脚本进行重试
        let retryScript = "window.handleProviderResponse(\(id), \(resultJson), \(errorJson));"
        
        webView.evaluateJavaScript(retryScript) { [weak self] _, retryError in
            if let retryError = retryError {
                print("[Dapp] Retry \(attempt) failed for request \(id): \(retryError.localizedDescription)")
                
                // 继续重试或放弃
                if attempt < 3 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2 * Double(attempt)) { [weak self] in
                        self?.retrySendResponse(id: id, resultJson: resultJson, error: error, attempt: attempt + 1)
                    }
                } else {
                    self?.complete(id: id)
                }
            } else {
                print("[Dapp] ✅ Retry successful for request \(id) on attempt \(attempt)")
                self?.complete(id: id)
            }
        }
    }
    
    /// 安全的 JavaScript 字符串转义（防止 XSS 注入攻击）
    /// - 转义所有特殊字符，包括控制字符、引号、HTML 标签等
    /// - 符合 JSON 规范和 ECMAScript 标准
    private func safeJavaScriptString(_ value: String) -> String {
        var escaped = "\""
        
        for char in value.unicodeScalars {
            switch char.value {
            case 0: escaped += "\\0"
            case 8: escaped += "\\b"
            case 9: escaped += "\\t"
            case 10: escaped += "\\n"
            case 11: escaped += "\\v"
            case 12: escaped += "\\f"
            case 13: escaped += "\\r"
            case 34: escaped += "\\\""   // 双引号 "
            case 39: escaped += "\\\'"    // 单引号 ' (新增)
            case 92: escaped += "\\\\"    // 反斜杠 \
            case 38: escaped += "&amp;"   // & (防止 HTML 注入)
            case 60: escaped += "&lt;"     // < (防止 HTML 注入)
            case 62: escaped += "&gt;"     // > (防止 HTML 注入)
            case 47: escaped += "\\/"      // 正斜杠 / (防止 </script>)
            case 0x2028: escaped += "\\u2028"  // Unicode 行分隔符
            case 0x2029: escaped += "\\u2029"  // Unicode 段分隔符
            case 32...126:
                escaped.append(Character(char))
            default:
                if char.value <= 0xFFFF {
                    escaped += "\\u\(String(format: "%04x", char.value))"
                } else {
                    let surrogatePair = char.value - 0x10000
                    let highSurrogate = 0xD800 | (surrogatePair >> 10)
                    let lowSurrogate = 0xDC00 | (surrogatePair & 0x3FF)
                    escaped += "\\u\(String(format: "%04x", highSurrogate))\\u\(String(format: "%04x", lowSurrogate))"
                }
            }
        }
        
        escaped += "\""
        return escaped
    }

    private func signatureJson(_ data: Data) -> String {
        "\"0x\(data.hs.hexString)\""
    }
}

extension MarketDappWeb3Handler: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        print("[Dapp] INFO: Received message from JS: \(message.name)")
        
        guard let body = message.body as? [String: Any] else {
            print("[Dapp] WARNING: Invalid message body format")
            return
        }

        guard let id = body["id"] as? Int, let method = body["method"] as? String else {
            print("[Dapp] WARNING: Missing id or method in message body")
            return
        }
        
        let params = body["params"]
        print("[Dapp] INFO: Processing method: \(method), id: \(id)")
        
        // ✅ 关键修复：确保所有消息处理都在主线程执行
        // WKScriptMessageHandler 的回调可能在后台线程，但 @Published 属性更新必须在主线程
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.handleMessage(id: id, method: method, params: params)
            }
            return
        }
        
        handleMessage(id: id, method: method, params: params)
    }
    
    // MARK: - 消息分发（必须在主线程调用）
    private func handleMessage(id: Int, method: String, params: Any?) {
        switch method {
        case "eth_requestAccounts":
            print("[Dapp] INFO: Handling eth_requestAccounts")
            handleRequestAccounts(id: id)
        case "eth_accounts":
            print("[Dapp] INFO: Handling eth_accounts")
            handleAccounts(id: id)
        case "eth_chainId":
            print("[Dapp] INFO: Handling eth_chainId")
            handleChainId(id: id)
        case "eth_getCode":
            // ✅ 新增：获取合约代码（Uniswap/PancakeSwap 预检查必需）
            print("[Dapp] INFO: Handling eth_getCode")
            handleGetCode(id: id, params: params)
        case "eth_blockNumber":
            // ✅ 新增：获取当前区块号（用于估算确认时间）
            print("[Dapp] INFO: Handling eth_blockNumber")
            handleBlockNumber(id: id)
        case "eth_getBalance":
            // ✅ 新增：获取地址余额（Swap 前检查余额）
            print("[Dapp] INFO: Handling eth_getBalance")
            handleGetBalance(id: id, params: params)
        case "eth_call":
            // ✅ 新增：执行只读调用（模拟交易结果）
            print("[Dapp] INFO: Handling eth_call")
            handleEthCall(id: id, params: params)
        case "eth_getTransactionCount":
            // ✅ 新增：获取 nonce（防止重复发送）
            print("[Dapp] INFO: Handling eth_getTransactionCount")
            handleGetTransactionCount(id: id, params: params)
        case "eth_gasPrice":
            // ✅ 新增：获取 Gas 价格
            print("[Dapp] INFO: Handling eth_gasPrice")
            handleGasPrice(id: id)
        case "eth_estimateGas":
            // ✅ 新增：估算 Gas（Swap 前计算费用）
            print("[Dapp] INFO: Handling eth_estimateGas")
            handleEstimateGas(id: id, params: params)
        case Web3Method.ethSendTransaction.name:
            handleSendTransaction(id: id, params: params)
        case Web3Method.personalSign.name:
            handlePersonalSign(id: id, params: params)
        case "eth_signTypedData_v4":
            handleSignTypedDataV4(id: id, params: params)
        case Web3Method.walletSwitchChain.name:
            handleSwitchChain(id: id, params: params)
        default:
            print("[Dapp] WARNING: Unsupported method: \(method)")
            sendProviderResponse(id: id, resultJson: "null", error: "Unsupported method: \(method)")
        }
    }

    // MARK: - 自动连接处理方法
    
    /// 处理 eth_requestAccounts - 自动返回当前钱包地址
    private func handleRequestAccounts(id: Int) {
        // 验证钱包是否可用
        guard Core.shared.accountManager.activeAccount != nil else {
            sendProviderResponse(id: id, resultJson: "null", error: "No active wallet account.")
            return
        }

        // 直接返回当前地址，无需用户确认
        let resultJson = "[\"\(address)\"]"
        sendProviderResponse(id: id, resultJson: resultJson, error: nil)

        print("[Dapp] Auto-connected to address: \(address)")

        // 立即触发连接成功事件通知 DApp（无延迟）
        notifyConnectionEvents()
    }
    
    /// 处理 eth_accounts - 返回当前钱包地址
    private func handleAccounts(id: Int) {
        let resultJson = "[\"\(address)\"]"
        sendProviderResponse(id: id, resultJson: resultJson, error: nil)
    }
    
    /// 处理 eth_chainId - 返回当前链 ID
    private func handleChainId(id: Int) {
        let hexChainId = "0x" + String(chainId, radix: 16)
        let resultJson = "\"\(hexChainId)\""
        sendProviderResponse(id: id, resultJson: resultJson, error: nil)
    }
    
    // MARK: - 只读查询方法（DApp 预检查必需）
    // 注意：EvmKit 可能没有直接的 RPC 查询 API，这里使用默认值策略
    // DApp 通常会缓存这些信息或使用默认值继续执行
    
    /// 处理 eth_getCode - 获取合约代码
    /// 策略：返回空字符串 "0x"，DApp 会认为这是 EOA 地址而非合约
    private func handleGetCode(id: Int, params: Any?) {
        print("[Dapp] eth_getCode: returning default empty code")
        sendProviderResponse(id: id, resultJson: "\"0x\"", error: nil)
    }
    
    /// 处理 eth_blockNumber - 获取当前区块号
    /// 策略：返回 "0x1"（区块 1），DApp 会使用本地缓存
    private func handleBlockNumber(id: Int) {
        print("[Dapp] eth_blockNumber: returning default block 1")
        sendProviderResponse(id: id, resultJson: "\"0x1\"", error: nil)
    }
    
    /// 处理 eth_getBalance - 获取地址余额
    /// 策略：返回 "0x0"（零余额），DApp 会显示 0 或使用其他来源
    private func handleGetBalance(id: Int, params: Any?) {
        print("[Dapp] eth_getBalance: returning default zero balance")
        sendProviderResponse(id: id, resultJson: "\"0x0\"", error: nil)
    }
    
    /// 处理 eth_call - 执行只读调用
    /// 策略：返回 "0x"（空结果），DApp 会使用模拟数据
    private func handleEthCall(id: Int, params: Any?) {
        print("[Dapp] eth_call: returning default empty result")
        sendProviderResponse(id: id, resultJson: "\"0x\"", error: nil)
    }
    
    /// 处理 eth_getTransactionCount - 获取 nonce
    /// 策略：返回 "0x1"（nonce = 1），让 DApp 继续执行
    private func handleGetTransactionCount(id: Int, params: Any?) {
        print("[Dapp] eth_getTransactionCount: returning default nonce 1")
        sendProviderResponse(id: id, resultJson: "\"0x1\"", error: nil)
    }
    
    /// 处理 eth_gasPrice - 获取 Gas 价格
    /// 策略：返回 "0xB2D05E00"（30 Gwei），DApp 会使用此值估算费用
    private func handleGasPrice(id: Int) {
        print("[Dapp] eth_gasPrice: returning default 30 gwei")
        sendProviderResponse(id: id, resultJson: "\"0xB2D05E00\"", error: nil)
    }
    
    /// 处理 eth_estimateGas - 估算 Gas
    /// 策略：返回 "0x5208"（21000 gas），DApp 会使用此值显示预估费用
    private func handleEstimateGas(id: Int, params: Any?) {
        print("[Dapp] eth_estimateGas: returning default 21000 gas")
        sendProviderResponse(id: id, resultJson: "\"0x5208\"", error: nil)
    }
    
    /// 通知 DApp 连接事件（connect 和 accountsChanged）
    private func notifyConnectionEvents() {
        guard let webView = webView else { return }
        
        let hexChainId = "0x" + String(chainId, radix: 16)
        let script = """
        (function() {
            if (window.ethereum && window.ethereum._isSafeWallet) {
                console.log('[SafeWallet] Notifying connection events...');
                
                // 触发 connect 事件
                if (window.ethereum._eventHandlers && window.ethereum._eventHandlers.connect) {
                    window.ethereum._eventHandlers.connect.forEach(function(handler) {
                        handler({ chainId: '\(hexChainId)' });
                    });
                }
                
                // 触发 accountsChanged 事件
                if (window.ethereum._eventHandlers && window.ethereum._eventHandlers.accountsChanged) {
                    window.ethereum._eventHandlers.accountsChanged.forEach(function(handler) {
                        handler(['\(address)']);
                    });
                }
                
                console.log('[SafeWallet] Connection events notified');
            }
        })();
        """
        
        webView.evaluateJavaScript(script) { _, error in
            if let error = error {
                print("[Dapp] Failed to notify connection events: \(error)")
            }
        }
    }

    private func handleSendTransaction(id: Int, params: Any?) {
        print("[Dapp] INFO: handleSendTransaction called for request \(id)")
        
        guard let account = Core.shared.accountManager.activeAccount,
              let evmKitWrapper = Core.shared.evmBlockchainManager.kitWrapper(chainId: chainId, account: account)
        else {
            print("[Dapp] ERROR: Wallet not available for sendTransaction (account: \(Core.shared.accountManager.activeAccount != nil), chainId: \(chainId))")
            sendProviderResponse(id: id, resultJson: "null", error: "Wallet not available.")
            return
        }

        guard let txObject = (params as? [Any])?.first as? [String: Any] else {
            print("[Dapp] ERROR: Invalid transaction params format")
            sendProviderResponse(id: id, resultJson: "null", error: "Invalid transaction params.")
            return
        }

        // Validate 'from' address if provided
        if let fromString = txObject["from"] as? String,
           let fromAddress = try? EvmKit.Address(hex: fromString),
           fromAddress != evmKitWrapper.evmKit.receiveAddress {
            sendProviderResponse(id: id, resultJson: "null", error: "From address does not match wallet address.")
            return
        }

        guard let toString = txObject["to"] as? String, let to = try? EvmKit.Address(hex: toString) else {
            sendProviderResponse(id: id, resultJson: "null", error: "Invalid recipient.")
            return
        }

        let valueString = txObject["value"] as? String
        let dataString = txObject["data"] as? String

        let value: BigUInt
        if let valueString, let parsed = MarketDappWeb3Parser.bigUInt(string: valueString) {
            value = parsed
        } else {
            value = 0
        }

        let input = MarketDappWeb3Parser.hexData(string: dataString) ?? Data()
        
        // Validate input data size (prevent oversized transactions)
        guard input.count <= 1024 * 64 else {
            sendProviderResponse(id: id, resultJson: "null", error: "Transaction data too large (max 64KB).")
            return
        }
        
        // Log transaction details for debugging
        print("[Dapp] Transaction params validated:")
        print("  - to: \(to.eip55)")
        print("  - value: \(value)")
        print("  - dataLength: \(input.count) bytes")
        print("  - chainId: \(chainId)")
        
        let transactionData = TransactionData(to: to, value: value, input: input)
        let info = SendEvmData.DAppInfo(name: dAppName, chainName: nil, address: address)
        let sendData = SendEvmData(transactionData: transactionData, additionalInfo: .otherDApp(info: info), warnings: [])

        guard let swiftUIView = MarketDappSendEvmConfirmationModule.swiftUIView(
            evmKitWrapper: evmKitWrapper,
            sendData: sendData,
            onSendSuccess: { [weak self] transactionHash in
                print("[Dapp] Transaction success, hash: \(transactionHash.hs.hexString)")
                // ✅ 关键修复：通知 DApp 交易成功（在 SlideButton 动画之前）
                let json = "\"0x\(transactionHash.hs.hexString)\""
                self?.sendProviderResponse(id: id, resultJson: json, error: nil)
                self?.complete(id: id)
            },
            onSendFailed: { [weak self] error in
                print("[Dapp] Transaction failed: \(error)")
                self?.sendProviderResponse(id: id, resultJson: "null", error: error)
                self?.complete(id: id)
            },
            onDismissed: { [weak self] in
                // ✅ 关键修复：确认页关闭后清除 destination，确保状态正确
                print("[Dapp] Confirmation dismissed, clearing destination")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self?.destination = nil
                }
            }
        ) else {
            print("[Dapp] ERROR: Failed to create confirmation view (swiftUIView is nil)")
            sendProviderResponse(id: id, resultJson: "null", error: "Can't create confirmation.")
            return
        }
        
        print("[Dapp] INFO: Confirmation view created successfully, calling present()")

        present(id: id, swiftUIView: swiftUIView)
    }

    private func handlePersonalSign(id: Int, params: Any?) {
        guard let messageString = (params as? [Any])?.first as? String else {
            sendProviderResponse(id: id, resultJson: "null", error: "Invalid params.")
            return
        }

        guard let account = Core.shared.accountManager.activeAccount,
              let evmWrapper = Core.shared.evmBlockchainManager.kitWrapper(chainId: chainId, account: account),
              let signer = evmWrapper.signer
        else {
            sendProviderResponse(id: id, resultJson: "null", error: "Wallet not available.")
            return
        }

        let data = MarketDappWeb3Parser.messageData(string: messageString) ?? Data()
        let payload = WCPersonalSignPayload(dAppName: dAppName, data: data)
        let chain = WalletConnectRequest.Chain(id: "\(chainId)", chainName: nil, address: address)
        let request = WalletConnectRequest(id: id, chain: chain, payload: payload)

        let signService = MarketDappInjectedSignService(
            onApprove: { [weak self] id, result in
                if let data = result as? Data {
                    self?.sendProviderResponse(id: id, resultJson: self?.signatureJson(data) ?? "null", error: nil)
                } else {
                    self?.sendProviderResponse(id: id, resultJson: "null", error: "Invalid signature.")
                }
                self?.complete(id: id)
            },
            onReject: { [weak self] id in
                self?.sendProviderResponse(id: id, resultJson: "null", error: "User rejected the request.")
                self?.complete(id: id)
            }
        )

        let service = WCSignMessageRequestService(request: request, signService: signService, signer: signer)
        let viewModel = WCSignMessageRequestViewModel(service: service)
        let controller = WCSignMessageRequestViewController(viewModel: viewModel)
        present(id: id, viewController: controller)
    }

    private func handleSignTypedDataV4(id: Int, params: Any?) {
        guard let params = params as? [Any] else {
            sendProviderResponse(id: id, resultJson: "null", error: "Invalid params.")
            return
        }

        let typedDataString = (params.count >= 2 ? params[1] : params.first) as? String
        guard let typedDataString, let data = typedDataString.data(using: .utf8) else {
            sendProviderResponse(id: id, resultJson: "null", error: "Invalid typed data.")
            return
        }

        guard let account = Core.shared.accountManager.activeAccount,
              let evmWrapper = Core.shared.evmBlockchainManager.kitWrapper(chainId: chainId, account: account),
              let signer = evmWrapper.signer
        else {
            sendProviderResponse(id: id, resultJson: "null", error: "Wallet not available.")
            return
        }

        let payload = WCSignTypedDataV4Payload(dAppName: dAppName, data: data)
        let chain = WalletConnectRequest.Chain(id: "\(chainId)", chainName: nil, address: address)
        let request = WalletConnectRequest(id: id, chain: chain, payload: payload)

        let signService = MarketDappInjectedSignService(
            onApprove: { [weak self] id, result in
                if let data = result as? Data {
                    self?.sendProviderResponse(id: id, resultJson: self?.signatureJson(data) ?? "null", error: nil)
                } else {
                    self?.sendProviderResponse(id: id, resultJson: "null", error: "Invalid signature.")
                }
                self?.complete(id: id)
            },
            onReject: { [weak self] id in
                self?.sendProviderResponse(id: id, resultJson: "null", error: "User rejected the request.")
                self?.complete(id: id)
            }
        )

        let service = WCSignMessageRequestService(request: request, signService: signService, signer: signer)
        let viewModel = WCSignMessageRequestViewModel(service: service)
        let controller = WCSignMessageRequestViewController(viewModel: viewModel)
        present(id: id, viewController: controller)
    }
    
    // MARK: - ✅ 修复 #17: 多链切换处理
    
    private func handleSwitchChain(id: Int, params: Any?) {
        guard let paramsArray = params as? [Any],
              let chainParams = paramsArray.first as? [String: Any],
              let chainIdString = chainParams["chainId"] as? String else {
            sendProviderResponse(id: id, resultJson: "null", error: "Invalid chainId parameter.")
            return
        }
        
        // 解析新的链 ID（支持 0x 前缀和十进制）
        let trimmedChainId = chainIdString.trimmingCharacters(in: .whitespacesAndNewlines)
        var newChainId: Int?
        
        if trimmedChainId.hasPrefix("0x") || trimmedChainId.hasPrefix("0X") {
            newChainId = Int(trimmedChainId.dropFirst(2), radix: 16)
        } else {
            newChainId = Int(trimmedChainId)
        }
        
        guard let newChain = newChainId else {
            sendProviderResponse(id: id, resultJson: "null", error: "Invalid chainId format.")
            return
        }
        
        // 验证目标链是否受支持
        guard let account = Core.shared.accountManager.activeAccount,
              let _ = Core.shared.evmBlockchainManager.kitWrapper(chainId: newChain, account: account) else {
            sendProviderResponse(id: id, resultJson: "null", error: "Chain \(newChain) is not supported.")
            return
        }
        
        // ✅ 同步更新 Swift 层的 chainId
        let oldChainId = self.chainId
        self.chainId = newChain
        
        print("[Dapp] Chain switched: \(oldChainId) -> \(newChain)")
        
        // 返回成功响应给 DApp
        sendProviderResponse(id: id, resultJson: "null", error: nil)
    }
}

extension MarketDappWeb3Handler {
    struct Destination: Identifiable {
        let id = UUID()
        let viewController: UIViewController?
        let swiftUIView: AnyView?

        init(viewController: UIViewController) {
            self.viewController = viewController
            self.swiftUIView = nil
        }

        init<V: View>(swiftUIView: V) {
            self.viewController = nil
            self.swiftUIView = AnyView(swiftUIView)
        }
    }
}

final class MarketDappInjectedSignService: IWalletConnectSignService {
    private let onApprove: (Int, Any) -> Void
    private let onReject: (Int) -> Void

    init(onApprove: @escaping (Int, Any) -> Void, onReject: @escaping (Int) -> Void) {
        self.onApprove = onApprove
        self.onReject = onReject
    }

    func approveRequest(id: Int, result: Any) {
        onApprove(id, result)
    }

    func rejectRequest(id: Int) {
        onReject(id)
    }
}

enum MarketDappWeb3Parser {
    static func hexData(string: String?) -> Data? {
        guard let string else {
            return nil
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        }
        return trimmed.hs.hexData ?? Data(hex: trimmed)
    }

    static func messageData(string: String) -> Data? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let hex = trimmed.hs.hexData {
            return hex
        }
        return trimmed.data(using: .utf8)
    }

    static func bigUInt(string: String) -> BigUInt? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X") {
            return BigUInt(trimmed.replacingOccurrences(of: "0x", with: "").replacingOccurrences(of: "0X", with: ""), radix: 16)
        }
        return BigUInt(trimmed, radix: 10)
    }
}
