import Foundation

struct ChildEnabledWallet: Codable, Equatable, Hashable {
    let parentAccountId: String?
    let childWalletId: String
    let tokenQueryId: String
    let coinName: String?
    let coinCode: String?
    let coinImage: String?
    let tokenDecimals: Int?

    init(
        parentAccountId: String? = nil,
        childWalletId: String,
        tokenQueryId: String,
        coinName: String? = nil,
        coinCode: String? = nil,
        coinImage: String? = nil,
        tokenDecimals: Int? = nil
    ) {
        self.parentAccountId = parentAccountId
        self.childWalletId = childWalletId
        self.tokenQueryId = tokenQueryId
        self.coinName = coinName
        self.coinCode = coinCode
        self.coinImage = coinImage
        self.tokenDecimals = tokenDecimals
    }

    init(parentAccountId: String? = nil, childWalletId: String, enabledWallet: EnabledWallet) {
        self.parentAccountId = parentAccountId
        self.childWalletId = childWalletId
        tokenQueryId = enabledWallet.tokenQueryId
        coinName = enabledWallet.coinName
        coinCode = enabledWallet.coinCode
        coinImage = enabledWallet.coinImage
        tokenDecimals = enabledWallet.tokenDecimals
    }

    init(parentAccountId: String? = nil, childWalletId: String, wallet: Wallet) {
        self.parentAccountId = parentAccountId
        self.childWalletId = childWalletId
        tokenQueryId = wallet.token.tokenQuery.id
        coinName = wallet.coin.name
        coinCode = wallet.coin.code
        coinImage = wallet.coin.image
        tokenDecimals = wallet.token.decimals
    }

    func enabledWallet(accountId: String) -> EnabledWallet {
        EnabledWallet(
            tokenQueryId: tokenQueryId,
            accountId: accountId,
            coinName: coinName,
            coinCode: coinCode,
            coinImage: coinImage,
            tokenDecimals: tokenDecimals
        )
    }
}
