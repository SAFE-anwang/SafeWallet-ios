import Combine
import Foundation
import MarketKit
import RxRelay
import RxSwift

public class WalletManager {
    private let accountManager: AccountManager
    private let storage: WalletStorage
    private var cancellables = Set<AnyCancellable>()

    private let activeWalletDataRelay = PublishRelay<WalletData>()
    private let activeWalletDataSubject = PassthroughSubject<WalletData, Never>()

    private let queue = DispatchQueue(label: "\(AppConfig.label).wallet_manager", qos: .userInitiated)

    private var cachedActiveWalletData = WalletData(wallets: [], account: nil, childWalletId: nil)

    public init(accountManager: AccountManager, storage: WalletStorage) {
        self.accountManager = accountManager
        self.storage = storage

        accountManager.activeAccountPublisher
            .sink { [weak self] _ in self?.reloadWallets() }
            .store(in: &cancellables)

        accountManager.accountDeletedPublisher
            .sink { [weak self] in self?.handleDelete(account: $0) }
            .store(in: &cancellables)

        ChildWalletBridge.shared.activeChildWalletChangedPublisher
            .sink { [weak self] change in self?.handleActiveChildWalletChanged(change) }
            .store(in: &cancellables)
    }

    private func handleActiveChildWalletChanged(_ change: ChildWalletBridge.ActiveChildWalletChange) {
        guard accountManager.activeAccount?.id == change.parentAccountId else {
            return
        }

        reloadWallets()
    }

    private func handleDelete(account: Account) {
        do {
            let accountWallets = try storage.wallets(account: account)
            storage.handle(newWallets: [], deletedWallets: accountWallets)
            try ChildWalletBridge.shared.delete(parentAccountId: account.id)
        } catch {
            // todo
        }
    }

    private func _reloadWallets() {
        if let activeAccount = accountManager.activeAccount {
            do {
                let wallets: [Wallet]
                let childWalletId = ChildWalletBridge.shared.activeChildWalletId(account: activeAccount)
                if let childWalletId {
                    wallets = try storage.wallets(childWalletId: childWalletId, account: activeAccount)
                } else {
                    wallets = try storage.wallets(account: activeAccount)
                }
                cachedActiveWalletData = WalletData(wallets: wallets, account: activeAccount, childWalletId: childWalletId)
            } catch {
                // todo
                cachedActiveWalletData = WalletData(wallets: [], account: activeAccount, childWalletId: ChildWalletBridge.shared.activeChildWalletId(account: activeAccount))
            }
        } else {
            cachedActiveWalletData = WalletData(wallets: [], account: nil, childWalletId: nil)
        }

        activeWalletDataRelay.accept(cachedActiveWalletData)
        activeWalletDataSubject.send(cachedActiveWalletData)
    }

    private func reloadWallets() {
        queue.async { [weak self] in self?._reloadWallets() }
    }
}

extension WalletManager {
    public var activeWalletData: WalletData {
        queue.sync { cachedActiveWalletData }
    }

    public var activeWallets: [Wallet] {
        activeWalletData.wallets
    }

    var activeWalletDataUpdatedObservable: Observable<WalletData> {
        activeWalletDataRelay.asObservable()
    }

    var activeWalletDataUpdatedPublisher: AnyPublisher<WalletData, Never> {
        activeWalletDataSubject.eraseToAnyPublisher()
    }

    func preloadWallets() {
        reloadWallets()
    }

    func wallets(account: Account) -> [Wallet] {
        do {
            return try storage.wallets(account: account)
        } catch {
            // todo
            return []
        }
    }

    func wallets(account: Account, childWalletId: String?) -> [Wallet] {
        do {
            if let childWalletId {
                return try storage.wallets(childWalletId: childWalletId, account: account)
            }

            return try storage.wallets(account: account)
        } catch {
            // todo
            return []
        }
    }

    func handle(newWallets: [Wallet], deletedWallets: [Wallet]) {
        if let activeAccount = accountManager.activeAccount,
           (newWallets + deletedWallets).allSatisfy({ $0.account.id == activeAccount.id })
        {
            do {
                if let unhandled = try ChildWalletBridge.shared.handleAndReturnUnhandled(newWallets: newWallets, deletedWallets: deletedWallets, account: activeAccount) {
                    if !unhandled.newWallets.isEmpty || !unhandled.deletedWallets.isEmpty {
                        storage.handle(newWallets: unhandled.newWallets, deletedWallets: unhandled.deletedWallets)
                    }
                    reloadWallets()
                    return
                }
            } catch {
                if ChildWalletBridge.shared.isChildWalletActive(account: activeAccount) {
                    reloadWallets()
                    return
                }
            }
        }

        storage.handle(newWallets: newWallets, deletedWallets: deletedWallets)
        reloadWallets()
    }

    func save(wallets: [Wallet]) {
        handle(newWallets: wallets, deletedWallets: [])
    }

    func save(enabledWallets: [EnabledWallet]) {
        if let activeAccount = accountManager.activeAccount,
           enabledWallets.allSatisfy({ $0.accountId == activeAccount.id })
        {
            do {
                if let unhandled = try ChildWalletBridge.shared.saveAndReturnUnhandled(enabledWallets: enabledWallets, account: activeAccount) {
                    if !unhandled.isEmpty {
                        storage.handle(newEnabledWallets: unhandled)
                    }
                    reloadWallets()
                    return
                }
            } catch {
                if ChildWalletBridge.shared.isChildWalletActive(account: activeAccount) {
                    reloadWallets()
                    return
                }
            }
        }

        storage.handle(newEnabledWallets: enabledWallets)
        reloadWallets()
    }

    func saveRoot(enabledWallets: [EnabledWallet], account: Account) {
        guard enabledWallets.allSatisfy({ $0.accountId == account.id }) else {
            return
        }

        storage.handle(newEnabledWallets: enabledWallets)
        reloadWallets()
    }

    func delete(wallets: [Wallet]) {
        handle(newWallets: [], deletedWallets: wallets)
    }

    func clearWallets() {
        storage.clearWallets()
    }
}

public extension WalletManager {
    struct WalletData {
        public let wallets: [Wallet]
        public let account: Account?
        public let childWalletId: String?
    }
}
