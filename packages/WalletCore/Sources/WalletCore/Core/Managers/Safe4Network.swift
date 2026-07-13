import EvmKit
import Foundation

enum Safe4Network {
    static var currentChainId: Int {
        AppConfig.isSafe4TestNet ? Chain.SafeFourTestNet.id : Chain.SafeFour.id
    }

    static func chainId(testNet: Bool) -> Int {
        testNet ? Chain.SafeFourTestNet.id : Chain.SafeFour.id
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
        }
    }
}
