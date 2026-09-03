import MarketKit

final class Safe4SRC20TokenClassifier {
    private let storage: Safe4CustomTokenStorage

    init(storage: Safe4CustomTokenStorage) {
        self.storage = storage
    }

    func isSRC20(tokenQuery: TokenQuery, chainId: Int) -> Bool {
        guard tokenQuery.blockchainType == .safe4 else {
            return false
        }

        guard case let .eip20(address) = tokenQuery.tokenType else {
            return false
        }

        return (try? storage.asset(address: address, chainId: chainId)) != nil
    }

    func isSRC20(enabledWallet: EnabledWallet, chainId: Int) -> Bool {
        guard let tokenQuery = TokenQuery(id: enabledWallet.tokenQueryId) else {
            return false
        }

        return isSRC20(tokenQuery: tokenQuery, chainId: chainId)
    }

    func isSRC20(wallet: Wallet, chainId: Int) -> Bool {
        isSRC20(tokenQuery: wallet.token.tokenQuery, chainId: chainId)
    }
}
