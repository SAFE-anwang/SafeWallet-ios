import Foundation

public class KitCleaner {
    private let accountManager: AccountManager

    public init(accountManager: AccountManager) {
        self.accountManager = accountManager
    }
}

public extension KitCleaner {
    func clear() {
        let accounts = accountManager.allAccounts
        let accountIds = accounts.map(\.id)
        let kitWalletIds = accountIds + ChildWalletBridge.shared.kitWalletIdsToKeep(parentAccounts: accounts)

        DispatchQueue.global(qos: .background).async {
            try? BitcoinAdapter.clear(except: kitWalletIds)
            try? LitecoinAdapter.clear(except: kitWalletIds)
            try? DogecoinAdapter.clear(except: kitWalletIds)
            try? BitcoinCashAdapter.clear(except: kitWalletIds)
            try? DashAdapter.clear(except: kitWalletIds)
            try? EvmAdapter.clear(except: kitWalletIds)
            try? EvmNftAdapter.clear(except: kitWalletIds)
            try? ZcashAdapter.clear(except: kitWalletIds)
            try? SafeCoinAdapter.clear(except: kitWalletIds)
            try? TronAdapter.clear(except: kitWalletIds)
            try? MoneroAdapter.clear(except: kitWalletIds)
            try? ZanoAdapter.clear(except: kitWalletIds)
        }
    }
}
