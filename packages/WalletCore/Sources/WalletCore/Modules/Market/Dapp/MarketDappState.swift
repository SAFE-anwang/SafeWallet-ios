import Foundation

enum DAppChainIdStorage {
    static let safe4ChainIdKey = "safe-wallet.safe4.chainId"

    static func safe4ChainId(userDefaultsStorage: UserDefaultsStorage) -> Int? {
        guard let chainId: Int = userDefaultsStorage.value(for: safe4ChainIdKey),
              Safe4Network.context(chainId: chainId) != nil
        else {
            return nil
        }

        return chainId
    }

    static func resolvedChainId(fallback chainId: Int, userDefaultsStorage: UserDefaultsStorage) -> Int {
        guard Safe4Network.context(chainId: chainId) != nil else {
            return chainId
        }

        return safe4ChainId(userDefaultsStorage: userDefaultsStorage) ?? chainId
    }

    static func storeSafe4ChainId(_ chainId: Int, userDefaultsStorage: UserDefaultsStorage) {
        guard Safe4Network.context(chainId: chainId) != nil else {
            return
        }

        userDefaultsStorage.set(value: chainId, for: safe4ChainIdKey)
    }
}
