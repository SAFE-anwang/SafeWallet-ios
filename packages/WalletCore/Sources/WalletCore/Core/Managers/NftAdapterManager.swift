import Foundation
import MarketKit
import Combine
import RxRelay
import RxSwift

class NftAdapterManager {
    private let walletManager: WalletManager
    private let accountManager: AccountManager
    private let evmBlockchainManager: EvmBlockchainManager
    private let disposeBag = DisposeBag()
    private var cancellables = Set<AnyCancellable>()

    private let adaptersUpdatedRelay = PublishRelay<[NftKey: INftAdapter]>()
    private var _adapterMap = [NftKey: INftAdapter]()
    private var started = false

    private let queue = DispatchQueue(label: "\(AppConfig.label).nft-adapter_manager", qos: .userInitiated)

    init(walletManager: WalletManager, accountManager: AccountManager, evmBlockchainManager: EvmBlockchainManager) {
        self.walletManager = walletManager
        self.accountManager = accountManager
        self.evmBlockchainManager = evmBlockchainManager

        accountManager.activeAccountPublisher
            .sink { [weak self] account in
                self?.handleActiveAccountChanged(account: account)
            }
            .store(in: &cancellables)

        walletManager.activeWalletDataUpdatedObservable
            .observeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .subscribe(onNext: { [weak self] walletData in
                self?.handleAdaptersReady(wallets: walletData.wallets, account: walletData.account, childWalletId: walletData.childWalletId)
            })
            .disposed(by: disposeBag)

        for blockchain in evmBlockchainManager.allBlockchains {
            if let manager = try? evmBlockchainManager.evmKitManager(blockchainType: blockchain.type) {
                subscribe(disposeBag, manager.evmKitUpdatedObservable) { [weak self] in
                    self?.handleUpdatedEvmKit(blockchainType: blockchain.type)
                }
            }
        }

        // Wallet data is preloaded after Core.initApp publishes Core.shared. Creating an EVM
        // kit here would resolve mnemonic addresses through Core.shared during Core construction.
        // The wallet-data subscription above performs the same initialization after publication.
    }

    // EVM mnemonic addresses resolve through Core.shared. Start only after Core.initApp
    // publishes the Core instance, while still initializing adapters for an already active wallet.
    func start() {
        queue.async {
            guard !self.started else {
                return
            }

            self.started = true
            let account = self.accountManager.activeAccount
            self._initAdapters(
                wallets: self.walletManager.activeWallets,
                account: account,
                childWalletId: account.flatMap { ChildWalletBridge.shared.activeChildWalletId(account: $0) }
            )
        }
    }

    private func _initAdapters(wallets: [Wallet], account: Account?, childWalletId: String?, notify: Bool = true) {
        guard let account else {
            _adapterMap = [:]
            if notify {
                adaptersUpdatedRelay.accept(_adapterMap)
            }
            return
        }

        var blockchainTypes = Set(wallets.map { $0.token.blockchainType })
        for blockchainType in EvmBlockchainManager.blockchainTypes where !blockchainType.supportedNftTypes.isEmpty {
            blockchainTypes.insert(blockchainType)
        }

        let nftKeys = Array(Set(blockchainTypes.map { NftKey(account: account, blockchainType: $0, childWalletId: childWalletId) }))

        var newAdapterMap = [NftKey: INftAdapter]()

        for nftKey in nftKeys {
            if let adapter = _adapterMap[nftKey] {
                newAdapterMap[nftKey] = adapter
                continue
            }

            guard !nftKey.blockchainType.supportedNftTypes.isEmpty,
                  evmBlockchainManager.blockchain(type: nftKey.blockchainType) != nil,
                  let evmKitWrapper = try? evmBlockchainManager
                      .evmKitManager(blockchainType: nftKey.blockchainType)
                      .evmKitWrapper(account: nftKey.account, blockchainType: nftKey.blockchainType),
                  let nftKit = evmKitWrapper.nftKit
            else {
                continue
            }

            newAdapterMap[nftKey] = EvmNftAdapter(
                blockchainType: nftKey.blockchainType,
                evmKitWrapper: evmKitWrapper,
                nftKit: nftKit
            )
        }

//        print("NEW ADAPTERS: \(newAdapterMap.keys)")
        _adapterMap = newAdapterMap
        if notify {
            adaptersUpdatedRelay.accept(newAdapterMap)
        }
    }

    private func handleAdaptersReady(wallets: [Wallet], account: Account?, childWalletId: String?) {
        queue.async {
            guard self.started else {
                return
            }

            self._initAdapters(wallets: wallets, account: account, childWalletId: childWalletId)
        }
    }

    private func handleActiveAccountChanged(account: Account?) {
        queue.async {
            guard self.started else {
                return
            }

            guard self._adapterMap.keys.contains(where: { $0.account != account }) else {
                return
            }

            self._adapterMap = [:]
            self.adaptersUpdatedRelay.accept([:])
        }
    }

    private func handleUpdatedEvmKit(blockchainType: BlockchainType) {
        queue.async {
            guard self.started else {
                return
            }

            guard let account = self.accountManager.activeAccount else {
                return
            }

            self._adapterMap = self._adapterMap.filter { key, _ in
                !(key.account == account && key.blockchainType == blockchainType)
            }
            self._initAdapters(wallets: self.walletManager.activeWallets, account: account, childWalletId: ChildWalletBridge.shared.activeChildWalletId(account: account))
        }
    }
}

extension NftAdapterManager {
    func initAdaptersIfNeeded() {
        queue.async {
            guard self._adapterMap.isEmpty else {
                return
            }

            self._initAdapters(
                wallets: self.walletManager.activeWallets,
                account: self.accountManager.activeAccount,
                childWalletId: self.accountManager.activeAccount.flatMap { ChildWalletBridge.shared.activeChildWalletId(account: $0) }
            )
        }
    }

    func ensureAdapters(for account: Account?) {
        queue.async {
            let childWalletId = account.flatMap { ChildWalletBridge.shared.activeChildWalletId(account: $0) }
            let hasOnlyCurrentAccountAdapters = self._adapterMap.keys.allSatisfy { $0.account == account && $0.childWalletId == childWalletId }
            guard self._adapterMap.isEmpty || !hasOnlyCurrentAccountAdapters else {
                return
            }

            self._initAdapters(wallets: self.walletManager.activeWallets, account: account, childWalletId: childWalletId)
        }
    }

    var adapterMap: [NftKey: INftAdapter] {
        queue.sync { _adapterMap }
    }

    var adaptersUpdatedObservable: Observable<[NftKey: INftAdapter]> {
        adaptersUpdatedRelay.asObservable()
    }

    func adapter(nftKey: NftKey) -> INftAdapter? {
        queue.sync { _adapterMap[nftKey] }
    }

    func ensuredAdapter(nftKey: NftKey) -> INftAdapter? {
        let result: (adapter: INftAdapter?, notification: [NftKey: INftAdapter]?) = queue.sync {
            let hasOnlyCurrentAccountAdapters = _adapterMap.keys.allSatisfy { $0.account == nftKey.account && $0.childWalletId == nftKey.childWalletId }
            if _adapterMap.isEmpty || !hasOnlyCurrentAccountAdapters {
                _initAdapters(wallets: walletManager.activeWallets, account: nftKey.account, childWalletId: nftKey.childWalletId, notify: false)
                return (_adapterMap[nftKey], _adapterMap)
            }

            return (_adapterMap[nftKey], nil)
        }

        if let notification = result.notification {
            adaptersUpdatedRelay.accept(notification)
        }

        return result.adapter
    }

    func ensuredAdapterAsync(nftKey: NftKey) async -> INftAdapter? {
        ensuredAdapter(nftKey: nftKey)
    }

    func refresh() {
        queue.async {
            for adapter in self._adapterMap.values {
                adapter.sync()
            }
        }
    }
}
