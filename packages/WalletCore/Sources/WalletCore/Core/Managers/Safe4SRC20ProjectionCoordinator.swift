import Combine
import Foundation
import MarketKit

final class Safe4SRC20ProjectionCoordinator {
    private let migrationKey = "safe4-src20-enabled-wallets-migrated-v1"

    private let accountManager: AccountManager
    private let walletManager: WalletManager
    private let safe4SRC20EnabledWalletStorage: Safe4SRC20EnabledWalletStorage
    private let src20TokenClassifier: Safe4SRC20TokenClassifier
    private let userDefaultsStorage: UserDefaultsStorage
    private var cancellables = Set<AnyCancellable>()

    init(
        accountManager: AccountManager,
        walletManager: WalletManager,
        safe4SRC20EnabledWalletStorage: Safe4SRC20EnabledWalletStorage,
        src20TokenClassifier: Safe4SRC20TokenClassifier,
        userDefaultsStorage: UserDefaultsStorage
    ) {
        self.accountManager = accountManager
        self.walletManager = walletManager
        self.safe4SRC20EnabledWalletStorage = safe4SRC20EnabledWalletStorage
        self.src20TokenClassifier = src20TokenClassifier
        self.userDefaultsStorage = userDefaultsStorage

        walletManager.onWalletMutation = { [weak self] newWallets, deletedWallets, source in
            self?.handleWalletMutation(newWallets: newWallets, deletedWallets: deletedWallets, source: source)
        }
        walletManager.onEnabledWalletMutation = { [weak self] newEnabledWallets, deletedEnabledWallets, source in
            self?.handleEnabledWalletMutation(newEnabledWallets: newEnabledWallets, deletedEnabledWallets: deletedEnabledWallets, source: source)
        }

        accountManager.accountDeletedPublisher
            .sink { [weak self] account in
                self?.safe4SRC20EnabledWalletStorage.delete(accountId: account.id)
            }
            .store(in: &cancellables)

        migrateIfNeeded()
        project(chainId: Safe4Network.currentChainId)
    }

    func prepareSwitch(from chainId: Int) {
        syncSourceStorage(chainId: chainId)
    }

    func project(chainId: Int, replacing sourceChainId: Int? = nil) {
        let projected = src20EnabledWallets(chainId: chainId)
        let currentProjected = src20EnabledWallets(chainId: sourceChainId ?? chainId)

        guard !projected.isEmpty || !currentProjected.isEmpty else {
            return
        }

        let projectedByKey = projected.reduce(into: [String: EnabledWallet]()) { $0[enabledWalletKey($1)] = $1 }
        let currentByKey = currentProjected.reduce(into: [String: EnabledWallet]()) { $0[enabledWalletKey($1)] = $1 }

        let newEnabledWallets = projected.filter {
            guard let current = currentByKey[enabledWalletKey($0)] else {
                return true
            }

            return !sameEnabledWallet($0, current)
        }

        let deletedEnabledWallets = currentProjected.filter {
            projectedByKey[enabledWalletKey($0)] == nil
        }

        guard !newEnabledWallets.isEmpty || !deletedEnabledWallets.isEmpty else {
            return
        }

        walletManager.save(
            enabledWallets: newEnabledWallets,
            deletedEnabledWallets: deletedEnabledWallets,
            source: .projection
        )
    }

    func projectAndWait(chainId: Int, replacing sourceChainId: Int) async {
        project(chainId: chainId, replacing: sourceChainId)
        await walletManager.preloadWalletsAndWait()
    }

    func reconcileCurrentChain(chainId: Int) {
        guard Safe4Network.isCurrent(chainId: chainId) else {
            return
        }

        syncSourceStorage(chainId: chainId)
        project(chainId: chainId)
    }

    private func migrateIfNeeded() {
        let migrated: Bool = userDefaultsStorage.value(for: migrationKey) ?? false
        guard !migrated else {
            return
        }

        syncSourceStorage(chainId: Safe4Network.currentChainId)
        userDefaultsStorage.set(value: true, for: migrationKey)
    }

    private func syncSourceStorage(chainId: Int) {
        for account in accountManager.allAccounts {
            let enabledWallets = walletManager.wallets(account: account)
                .filter { src20TokenClassifier.isSRC20(wallet: $0, chainId: chainId) }
                .map(enabledWallet(wallet:))
            safe4SRC20EnabledWalletStorage.replace(accountId: account.id, chainId: chainId, enabledWallets: enabledWallets)
        }
    }

    private func handleWalletMutation(newWallets: [Wallet], deletedWallets: [Wallet], source: WalletMutationSource) {
        guard source == .user else {
            return
        }

        let chainId = Safe4Network.currentChainId
        let newEnabledWallets = newWallets
            .filter { src20TokenClassifier.isSRC20(wallet: $0, chainId: chainId) }
            .map(enabledWallet(wallet:))
        let deletedEnabledWallets = deletedWallets
            .filter { src20TokenClassifier.isSRC20(wallet: $0, chainId: chainId) }
            .map(enabledWallet(wallet:))

        guard !newEnabledWallets.isEmpty || !deletedEnabledWallets.isEmpty else {
            return
        }

        safe4SRC20EnabledWalletStorage.handle(
            newEnabledWallets: newEnabledWallets,
            deletedEnabledWallets: deletedEnabledWallets,
            chainId: chainId
        )
    }

    private func handleEnabledWalletMutation(newEnabledWallets: [EnabledWallet], deletedEnabledWallets: [EnabledWallet], source: WalletMutationSource) {
        guard source == .user else {
            return
        }

        let chainId = Safe4Network.currentChainId
        let newSafe4EnabledWallets = newEnabledWallets
            .filter { src20TokenClassifier.isSRC20(enabledWallet: $0, chainId: chainId) }
        let deletedSafe4EnabledWallets = deletedEnabledWallets
            .filter { src20TokenClassifier.isSRC20(enabledWallet: $0, chainId: chainId) }

        guard !newSafe4EnabledWallets.isEmpty || !deletedSafe4EnabledWallets.isEmpty else {
            return
        }

        safe4SRC20EnabledWalletStorage.handle(
            newEnabledWallets: newSafe4EnabledWallets,
            deletedEnabledWallets: deletedSafe4EnabledWallets,
            chainId: chainId
        )
    }

    private func src20EnabledWallets(chainId: Int) -> [EnabledWallet] {
        safe4SRC20EnabledWalletStorage.enabledWallets(chainId: chainId)
            .filter { src20TokenClassifier.isSRC20(enabledWallet: $0, chainId: chainId) }
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

    private func enabledWalletKey(_ enabledWallet: EnabledWallet) -> String {
        "\(enabledWallet.accountId)|\(enabledWallet.tokenQueryId.lowercased())"
    }

    private func sameEnabledWallet(_ lhs: EnabledWallet, _ rhs: EnabledWallet) -> Bool {
        lhs.tokenQueryId.lowercased() == rhs.tokenQueryId.lowercased()
            && lhs.accountId == rhs.accountId
            && lhs.coinName == rhs.coinName
            && lhs.coinCode == rhs.coinCode
            && lhs.coinImage == rhs.coinImage
            && lhs.tokenDecimals == rhs.tokenDecimals
    }

}
