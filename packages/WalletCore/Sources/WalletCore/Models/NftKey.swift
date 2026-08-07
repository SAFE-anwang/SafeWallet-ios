import MarketKit

struct NftKey: Hashable {
    let account: Account
    let blockchainType: BlockchainType
    let childWalletId: String?

    init(account: Account, blockchainType: BlockchainType) {
        self.init(account: account, blockchainType: blockchainType, childWalletId: ChildWalletBridge.shared.activeChildWalletId(account: account))
    }

    init(account: Account, blockchainType: BlockchainType, childWalletId: String?) {
        self.account = account
        self.blockchainType = blockchainType
        self.childWalletId = childWalletId
    }

    var storageAccountId: String {
        guard let childWalletId else {
            return account.id
        }

        return [account.id, "child", childWalletId].joined(separator: ":")
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(account)
        hasher.combine(blockchainType)
        hasher.combine(childWalletId)
    }

    static func == (lhs: NftKey, rhs: NftKey) -> Bool {
        lhs.account == rhs.account && lhs.blockchainType == rhs.blockchainType && lhs.childWalletId == rhs.childWalletId
    }
}
