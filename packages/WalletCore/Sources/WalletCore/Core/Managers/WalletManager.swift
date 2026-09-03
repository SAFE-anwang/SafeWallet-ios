import Combine
import Foundation
import MarketKit
import RxRelay
import RxSwift

enum WalletMutationSource: Equatable {
    case user
    case projection
}

public class WalletManager {
    private let accountManager: AccountManager
    private let storage: WalletStorage
    private var cancellables = Set<AnyCancellable>()

    private let activeWalletDataRelay = PublishRelay<WalletData>()
    private let activeWalletDataSubject = PassthroughSubject<WalletData, Never>()

    private let queue = DispatchQueue(label: "\(AppConfig.label).wallet_manager", qos: .userInitiated)

    private var cachedActiveWalletData = WalletData(wallets: [], account: nil, childWalletId: nil)

    var onWalletMutation: (([Wallet], [Wallet], WalletMutationSource) -> Void)?
    var onEnabledWalletMutation: (([EnabledWallet], [EnabledWallet], WalletMutationSource) -> Void)?

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
                let childWalletId = ChildWalletBridge.shared.activeChildWalletId(account: activeAccount)
                let wallets = try childWalletId.map { try storage.wallets(childWalletId: $0, account: activeAccount) } ?? storage.wallets(account: activeAccount)
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

    private func reloadWalletsAndWait() async {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                self?._reloadWallets()
                continuation.resume()
            }
        }
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

    func preloadWalletsAndWait() async {
        await reloadWalletsAndWait()
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
            return []
        }
    }

    func handle(newWallets: [Wallet], deletedWallets: [Wallet], source: WalletMutationSource = .user) {
        if source == .user,
           let activeAccount = accountManager.activeAccount,
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
        onWalletMutation?(newWallets, deletedWallets, source)
    }

    func save(wallets: [Wallet], source: WalletMutationSource = .user) {
        handle(newWallets: wallets, deletedWallets: [], source: source)
    }

    func save(enabledWallets: [EnabledWallet], deletedEnabledWallets: [EnabledWallet] = [], source: WalletMutationSource = .user) {
        if source == .user,
           deletedEnabledWallets.isEmpty,
           let activeAccount = accountManager.activeAccount,
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

        storage.handle(newEnabledWallets: enabledWallets, deletedEnabledWallets: deletedEnabledWallets)
        reloadWallets()
        onEnabledWalletMutation?(enabledWallets, deletedEnabledWallets, source)
    }

    func saveRoot(enabledWallets: [EnabledWallet], account: Account, source: WalletMutationSource = .user) {
        guard enabledWallets.allSatisfy({ $0.accountId == account.id }) else {
            return
        }

        storage.handle(newEnabledWallets: enabledWallets)
        reloadWallets()
        onEnabledWalletMutation?(enabledWallets, [], source)
    }

    func delete(wallets: [Wallet], source: WalletMutationSource = .user) {
        handle(newWallets: [], deletedWallets: wallets, source: source)
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
