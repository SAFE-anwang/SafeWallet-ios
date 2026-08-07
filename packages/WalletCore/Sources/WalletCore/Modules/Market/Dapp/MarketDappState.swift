import Foundation

enum DAppChainIdStorage {
    static let safe4ChainIdKey = "safe-wallet.safe4.chainId"

    static func safe4ChainId() -> Int? {
        Core.shared.userDefaultsStorage.value(for: safe4ChainIdKey)
    }

    static func resolvedChainId(fallback chainId: Int) -> Int {
        guard Safe4Network.context(chainId: chainId) != nil else {
            return chainId
        }

        return safe4ChainId() ?? chainId
    }

    static func storeSafe4ChainId(_ chainId: Int) {
        guard Safe4Network.context(chainId: chainId) != nil else {
            return
        }

        Core.shared.userDefaultsStorage.set(value: chainId, for: safe4ChainIdKey)
    }
}
