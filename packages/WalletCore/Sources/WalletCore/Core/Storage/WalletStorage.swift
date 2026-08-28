import MarketKit
import RxSwift

public class WalletStorage {
    private let marketKit: MarketKit.Kit
    private let storage: EnabledWalletStorage

    public init(marketKit: MarketKit.Kit, storage: EnabledWalletStorage) {
        self.marketKit = marketKit
        self.storage = storage
    }

    private func enabledWallet(wallet: Wallet) -> EnabledWallet {
        EnabledWallet(
            tokenQueryId: wallet.token.tokenQuery.id,
            accountId: wallet.account.id,
            coinName: wallet.coin.name,
            coinCode: wallet.coin.code,
            coinImage: wallet.coin.image,
            tokenDecimals: wallet.token.decimals
        )
    }

    private func usesStoredMetadata(token: Token, enabledWallet: EnabledWallet) -> Bool {
        let tokenQuery = token.tokenQuery
        guard tokenQuery.blockchainType == .safe4 else {
            return false
        }

        guard case .eip20 = tokenQuery.tokenType else {
            return false
        }

        return token.isCustom
            && enabledWallet.coinName != nil
            && enabledWallet.coinCode != nil
            && enabledWallet.tokenDecimals != nil
    }

    private func wallet(
        account: Account,
        enabledWallet: EnabledWallet,
        tokenQuery: TokenQuery,
        blockchain: Blockchain
    ) -> Wallet? {
        guard
            let coinName = enabledWallet.coinName,
            let coinCode = enabledWallet.coinCode,
            let tokenDecimals = enabledWallet.tokenDecimals
        else {
            return nil
        }

        let token = Token(
            coin: Coin(
                uid: tokenQuery.customCoinUid,
                name: coinName,
                code: coinCode,
                image: enabledWallet.coinImage
            ),
            blockchain: blockchain,
            type: tokenQuery.tokenType,
            decimals: tokenDecimals
        )

        return Wallet(token: token, account: account)
    }
}

extension WalletStorage {
    func wallets(account: Account) throws -> [Wallet] {
        let enabledWallets = try storage.enabledWallets(accountId: account.id)

        let queries = enabledWallets.compactMap { TokenQuery(id: $0.tokenQueryId) }
        let tokens = try marketKit.tokens(queries: queries)

        let blockchainUids = queries.map(\.blockchainType.uid)
        let blockchains = try marketKit.blockchains(uids: blockchainUids)

        return enabledWallets.compactMap { enabledWallet in
            guard let tokenQuery = TokenQuery(id: enabledWallet.tokenQueryId) else {
                return nil
            }

            if let token = tokens.first(where: { $0.tokenQuery == tokenQuery }) {
                if usesStoredMetadata(token: token, enabledWallet: enabledWallet),
                   let wallet = wallet(
                    account: account,
                    enabledWallet: enabledWallet,
                    tokenQuery: tokenQuery,
                    blockchain: token.blockchain
                   ) {
                    return wallet
                }

                return Wallet(token: token, account: account)
            }

            if let blockchain = blockchains.first(where: { $0.uid == tokenQuery.blockchainType.uid }),
               let wallet = wallet(
                account: account,
                enabledWallet: enabledWallet,
                tokenQuery: tokenQuery,
                blockchain: blockchain
               ) {
                return wallet
            }

            return nil
        }
    }

    func handle(newWallets: [Wallet], deletedWallets: [Wallet]) {
        let newEnabledWallets = newWallets.map { enabledWallet(wallet: $0) }
        let deletedEnabledWallets = deletedWallets.map { enabledWallet(wallet: $0) }
        try? storage.handle(newEnabledWallets: newEnabledWallets, deletedEnabledWallets: deletedEnabledWallets)
    }

    func handle(newEnabledWallets: [EnabledWallet], deletedEnabledWallets: [EnabledWallet] = []) {
        try? storage.handle(newEnabledWallets: newEnabledWallets, deletedEnabledWallets: deletedEnabledWallets)
    }

    func clearWallets() {
        try? storage.clear()
    }
}
