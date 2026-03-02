import EvmKit
import HsExtensions
import BigInt
import Foundation
import UIKit
import WebKit

final class MarketDappWeb3Handler: NSObject, ObservableObject {
    private let chainId: Int
    private let address: String
    private let dAppName: String

    @Published var destination: Destination?

    private var activeRequestId: Int?
    private weak var webView: WKWebView?

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

        activeRequestId = nil
        sendProviderResponse(id: id, resultJson: "null", error: "User rejected the request.")
    }

    private func complete(id: Int) {
        if activeRequestId == id {
            activeRequestId = nil
        }
    }

    private func present(id: Int, viewController: UIViewController) {
        activeRequestId = id
        destination = Destination(viewController: viewController)
    }

    private func sendProviderResponse(id: Int, resultJson: String, error: String?) {
        guard let webView else {
            return
        }

        let errorJson: String
        if let error {
            errorJson = "\"\(escapeForJavaScriptString(error))\""
        } else {
            errorJson = "null"
        }

        webView.evaluateJavaScript("window.handleProviderResponse(\(id), \(resultJson), \(errorJson));", completionHandler: nil)
    }

    private func escapeForJavaScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    private func signatureJson(_ data: Data) -> String {
        "\"0x\(data.hs.hexString)\""
    }
}

extension MarketDappWeb3Handler: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else {
            return
        }

        guard let id = body["id"] as? Int, let method = body["method"] as? String else {
            return
        }

        let params = body["params"]

        switch method {
        case Web3Method.ethSendTransaction.name:
            handleSendTransaction(id: id, params: params)
        case Web3Method.personalSign.name:
            handlePersonalSign(id: id, params: params)
        case "eth_signTypedData_v4":
            handleSignTypedDataV4(id: id, params: params)
        default:
            sendProviderResponse(id: id, resultJson: "null", error: "Unsupported method: \(method)")
        }
    }

    private func handleSendTransaction(id: Int, params: Any?) {
        guard let account = Core.shared.accountManager.activeAccount,
              let evmKitWrapper = Core.shared.evmBlockchainManager.kitWrapper(chainId: chainId, account: account)
        else {
            sendProviderResponse(id: id, resultJson: "null", error: "Wallet not available.")
            return
        }

        guard let txObject = (params as? [Any])?.first as? [String: Any] else {
            sendProviderResponse(id: id, resultJson: "null", error: "Invalid transaction params.")
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
        let transactionData = TransactionData(to: to, value: value, input: input)
        let info = SendEvmData.DAppInfo(name: dAppName, chainName: nil, address: address)
        let sendData = SendEvmData(transactionData: transactionData, additionalInfo: .otherDApp(info: info), warnings: [])

        guard let controller = MarketDappSendEvmConfirmationModule.viewController(
            evmKitWrapper: evmKitWrapper,
            sendData: sendData,
            onSendSuccess: { [weak self] transactionHash in
                let json = "\"0x\(transactionHash.hs.hexString)\""
                self?.sendProviderResponse(id: id, resultJson: json, error: nil)
                self?.complete(id: id)
            },
            onSendFailed: { [weak self] error in
                self?.sendProviderResponse(id: id, resultJson: "null", error: error)
                self?.complete(id: id)
            }
        ) else {
            sendProviderResponse(id: id, resultJson: "null", error: "Can't create confirmation.")
            return
        }

        present(id: id, viewController: controller)
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
}

extension MarketDappWeb3Handler {
    struct Destination: Identifiable {
        let id = UUID()
        let viewController: UIViewController
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
