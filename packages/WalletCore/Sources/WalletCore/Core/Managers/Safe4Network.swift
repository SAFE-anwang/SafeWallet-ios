import EvmKit
import Foundation

enum Safe4Network {
    static var currentChainId: Int {
        AppConfig.isSafe4TestNet ? Chain.SafeFourTestNet.id : Chain.SafeFour.id
    }

    static var currentContext: Safe4NetworkContext {
        context(testNet: AppConfig.isSafe4TestNet)
    }

    static func chainId(testNet: Bool) -> Int {
        testNet ? Chain.SafeFourTestNet.id : Chain.SafeFour.id
    }

    static func context(testNet: Bool) -> Safe4NetworkContext {
        testNet ? .testNet : .mainNet
    }

    static func context(chainId: Int) -> Safe4NetworkContext? {
        switch chainId {
        case Chain.SafeFour.id: return .mainNet
        case Chain.SafeFourTestNet.id: return .testNet
        default: return nil
        }
    }

    static func supportedContext(chainId: Int) throws -> Safe4NetworkContext {
        guard let context = context(chainId: chainId) else {
            throw Safe4NetworkError.unsupportedChain(chainId)
        }

        return context
    }

    static func activeContext(chainId: Int) throws -> Safe4NetworkContext {
        let context = try supportedContext(chainId: chainId)

        guard isCurrent(chainId: chainId) else {
            throw Safe4NetworkError.staleContext(expected: chainId, current: currentChainId)
        }

        return context
    }

    static func isCurrent(chainId: Int) -> Bool {
        chainId == currentChainId
    }

    static func deployContractsKey(chainId: Int) -> String {
        "\(Safe4CustomTokenManager.safe4DeployContractsKey)-\(chainId)"
    }

    static func logoKey(coinUid: String, chainId: Int) -> String {
        "\(coinUid.lowercased())-\(chainId)"
    }

    static func restoreDeployContractsCache(userDefaultsStorage: UserDefaultsStorage, chainId: Int = currentChainId) {
        if let addresses: [String] = userDefaultsStorage.value(for: deployContractsKey(chainId: chainId)) {
            userDefaultsStorage.set(value: addresses, for: Safe4CustomTokenManager.safe4DeployContractsKey)
        } else {
            userDefaultsStorage.set(value: [String](), for: Safe4CustomTokenManager.safe4DeployContractsKey)
        }
    }
}

enum Safe4NetworkError: LocalizedError {
    case unsupportedChain(Int)
    case staleContext(expected: Int, current: Int)

    var errorDescription: String? {
        switch self {
        case let .unsupportedChain(chainId): return "Unsupported SAFE4 chainId: \(chainId)"
        case let .staleContext(expected, current): return "SAFE4 network changed. Expected chainId \(expected), current chainId \(current)."
        }
    }
}

struct Safe4NetworkContext {
    let isTestNet: Bool
    let chain: Chain
    let rpcUrlString: String
    let apiBaseUrl: String
    let src20TimeLockAddress: String

    var chainId: Int {
        chain.id
    }

    var rpcUrl: URL {
        URL(string: rpcUrlString)!
    }
}

extension Notification.Name {
    static let safe4NetworkDidSwitch = Notification.Name("Safe4NetworkDidSwitch")
}

extension Safe4NetworkContext {
    static var mainNet: Safe4NetworkContext {
        Safe4NetworkContext(
            isTestNet: false,
            chain: .SafeFour,
            rpcUrlString: ApiKeyManager.rpcEndpoint(network: .safe4) ?? "https://safe4.anwang.com/rpc",
            apiBaseUrl: "https://safe4.anwang.com",
            src20TimeLockAddress: "0x6A6dFAF83cc1741FE08A9EFDea596dEad68f7420"
        )
    }

    static var testNet: Safe4NetworkContext {
        Safe4NetworkContext(
            isTestNet: true,
            chain: .SafeFourTestNet,
            rpcUrlString: ApiKeyManager.rpcEndpoint(network: .safe4_testnet) ?? "https://safe4testnet.anwang.com/rpc",
            apiBaseUrl: "https://safe4testnet.anwang.com",
            src20TimeLockAddress: "0x4f203092FB68732D8484c099a72dDc5a195f26f9"
        )
    }
}
