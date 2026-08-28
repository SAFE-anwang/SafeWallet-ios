import Combine
import Foundation
import MarketKit
import RxRelay
import RxSwift

enum WalletMutationSource {
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

    private var cachedActiveWalletData = WalletData(wallets: [], account: nil)

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
    }

    private func handleDelete(account: Account) {
        do {
            let accountWallets = try storage.wallets(account: account)
            storage.handle(newWallets: [], deletedWallets: accountWallets)
        } catch {
            // todo
        }
    }

    private func _reloadWallets() {
        if let activeAccount = accountManager.activeAccount {
            do {
                cachedActiveWalletData = try WalletData(wallets: storage.wallets(account: activeAccount), account: activeAccount)
            } catch {
                // todo
                cachedActiveWalletData = WalletData(wallets: [], account: activeAccount)
            }
        } else {
            cachedActiveWalletData = WalletData(wallets: [], account: nil)
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

    func handle(newWallets: [Wallet], deletedWallets: [Wallet], source: WalletMutationSource = .user) {
        storage.handle(newWallets: newWallets, deletedWallets: deletedWallets)
        reloadWallets()
        onWalletMutation?(newWallets, deletedWallets, source)
    }

    func save(wallets: [Wallet], source: WalletMutationSource = .user) {
        handle(newWallets: wallets, deletedWallets: [], source: source)
    }

    func save(enabledWallets: [EnabledWallet], deletedEnabledWallets: [EnabledWallet] = [], source: WalletMutationSource = .user) {
        storage.handle(newEnabledWallets: enabledWallets, deletedEnabledWallets: deletedEnabledWallets)
        reloadWallets()
        onEnabledWalletMutation?(enabledWallets, deletedEnabledWallets, source)
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
    }
}
