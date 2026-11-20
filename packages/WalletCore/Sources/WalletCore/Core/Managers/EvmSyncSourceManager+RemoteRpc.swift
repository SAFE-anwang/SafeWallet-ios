import EvmKit
import Foundation
import MarketKit

extension EvmSyncSourceManager {
    static func migratedSelectedEndpoint(current: String?, previous: String?, updated: String?) -> String? {
        guard let current, let previous, let updated = ApiKeyManager.validHttpEndpoint(updated),
              URL(string: previous)?.absoluteString == current,
              let updatedUrl = URL(string: updated)
        else {
            return nil
        }

        return updatedUrl.absoluteString
    }

    static func blockchainTypesToRefresh(
        for networks: Set<RpcNetworkName>,
        testNetEnabled: Bool,
        safe4IsTestNet: Bool
    ) -> Set<BlockchainType> {
        Set(networks.compactMap { network in
            guard Self.shouldRefresh(
                network: network,
                testNetEnabled: testNetEnabled,
                safe4IsTestNet: safe4IsTestNet
            ) else { return nil }
            return blockchainType(for: network)
        })
    }

    static func blockchainType(for network: RpcNetworkName) -> BlockchainType? {
        switch network {
        case .eth: return .ethereum
        case .bsc, .p2pify: return .binanceSmartChain
        case .polygon: return .polygon
        case .avax: return .avalanche
        case .optimism: return .optimism
        case .arbitrum: return .arbitrumOne
        case .gnosis: return .gnosis
        case .fantom: return .fantom
        case .safe4, .safe4_testnet: return .safe4
        case .sol: return nil
        }
    }

    private static func shouldRefresh(
        network: RpcNetworkName,
        testNetEnabled: Bool,
        safe4IsTestNet: Bool
    ) -> Bool {
        switch network {
        case .eth, .bsc, .p2pify:
            return !testNetEnabled
        case .safe4:
            return !safe4IsTestNet
        case .safe4_testnet:
            return safe4IsTestNet
        case .polygon, .avax, .optimism, .arbitrum, .gnosis, .fantom:
            return true
        case .sol:
            return false
        }
    }
}

extension RpcSource {

    static func safeEthereumRpcHttp() -> RpcSource {
        .http(urls: [URL(string: ApiKeyManager.rpcEndpoint(network: .eth) ?? "https://ethereum-mainnet.core.chainstack.com/a1911ee247f4f8de22c1f4e55865f616")!], auth: nil)
    }

    static func safeSolanaRpcHttp() -> RpcSource {
        .http(urls: [URL(string: ApiKeyManager.rpcEndpoint(network: .sol) ?? "https://solana-mainnet.core.chainstack.com/35d90e70a574359e50b11e10b5460414")!], auth: nil)
    }

    static func safeBscRpcHttp() -> RpcSource {
        .http(urls: [URL(string: ApiKeyManager.rpcEndpoint(network: .bsc) ?? "https://bsc-mainnet.core.chainstack.com/67f0d109c5c0b7f0aa251a89f12c0b7b")!], auth: nil)
    }

    static func p2pifyRpcHttp() -> RpcSource {
        .http(urls: [URL(string: ApiKeyManager.rpcEndpoint(network: .p2pify) ?? "https://nd-981-064-010.p2pify.com/3abdd3b90f012f4427380b632deb4180")!], auth: nil)
    }

    static func safePolygonRpcHttp() -> RpcSource {
        .http(urls: [URL(string: ApiKeyManager.rpcEndpoint(network: .polygon) ?? "https://polygon-mainnet.core.chainstack.com/789b8e5d616e6aa747001d3aeaef307d")!], auth: nil)
    }

    static func safeAvaxNetworkHttp() -> RpcSource {
        .http(urls: [URL(string: ApiKeyManager.rpcEndpoint(network: .avax) ?? "https://avalanche-mainnet.core.chainstack.com/ext/bc/C/rpc/0d78d62f3dc1baf5968e7bf78018ce02")!], auth: nil)
    }

    static func safeOptimismRpcHttp() -> RpcSource {
        .http(urls: [URL(string: ApiKeyManager.rpcEndpoint(network: .optimism) ?? "https://optimism-mainnet.core.chainstack.com/9f3d2000dae7846908ac871ef96e18fe")!], auth: nil)
    }

    static func safeArbitrumOneRpcHttp() -> RpcSource {
        .http(urls: [URL(string: ApiKeyManager.rpcEndpoint(network: .arbitrum) ?? "https://arbitrum-mainnet.core.chainstack.com/e60e242b446b1d6b703530d219df1cdc")!], auth: nil)
    }

    static func safeGnosisRpcHttp() -> RpcSource {
        .http(urls: [URL(string: ApiKeyManager.rpcEndpoint(network: .gnosis) ?? "https://nd-786-294-051.p2pify.com/4c89e746f92af4af9f76befc8dd64e59")!], auth: nil)
    }

    static func safeFantomRpcHttp() -> RpcSource {
        .http(urls: [URL(string: ApiKeyManager.rpcEndpoint(network: .fantom) ?? "https://fantom-mainnet.core.chainstack.com/01d412d3dbe245ad17742e58fa017171")!], auth: nil)
    }

    static func safeFourRpcHttp() -> RpcSource {
        .http(urls: [Safe4Network.currentContext.rpcUrl], auth: nil)
    }

}
