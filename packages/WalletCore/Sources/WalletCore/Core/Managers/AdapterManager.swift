import Foundation
import MarketKit
import RxRelay
import RxSwift

enum ZcashEndpointValidationError: LocalizedError {
    case noActiveAdapter
    case unavailable

    var errorDescription: String? {
        switch self {
        case .noActiveAdapter: return "No active Zcash adapter"
        case .unavailable: return "Zcash endpoint is unavailable"
        }
    }
}

class AdapterManager {
    private let disposeBag = DisposeBag()

    private let adapterFactory: AdapterFactory
    private let walletManager: WalletManager
    private let evmBlockchainManager: EvmBlockchainManager
    private let tronKitManager: TronKitManager
    private let tonKitManager: TonKitManager
    private let stellarKitManager: StellarKitManager
    private let zanoKitManager: ZanoKitManager
    private let solanaKitManager: SolanaKitManager
    private let moneroNodeManager: MoneroNodeManager
    private let zanoNodeManager: ZanoNodeManager
    private let zcashNodeManager: ZcashNodeManager

    private let adapterDataReadyRelay = PublishRelay<AdapterData>()

    private let queue = DispatchQueue(label: "\(AppConfig.label).adapter_manager", qos: .userInitiated)
    private let initAdaptersQueue = DispatchQueue(label: "\(AppConfig.label).adapter_manager.init_adapters", qos: .userInitiated)
    private var _adapterData = AdapterData(adapterMap: [:], account: nil, childWalletId: nil)
    private(set) var src20SyncManager: SRC20SyncManager?

    public init(adapterFactory: AdapterFactory, walletManager: WalletManager, evmBlockchainManager: EvmBlockchainManager,
                tronKitManager: TronKitManager, tonKitManager: TonKitManager, stellarKitManager: StellarKitManager, zanoKitManager: ZanoKitManager, solanaKitManager: SolanaKitManager,
                btcBlockchainManager: BtcBlockchainManager, moneroNodeManager: MoneroNodeManager, zanoNodeManager: ZanoNodeManager, zcashNodeManager: ZcashNodeManager)
    {
        self.adapterFactory = adapterFactory
        self.walletManager = walletManager
        self.evmBlockchainManager = evmBlockchainManager
        self.tronKitManager = tronKitManager
        self.tonKitManager = tonKitManager
        self.stellarKitManager = stellarKitManager
        self.zanoKitManager = zanoKitManager
        self.solanaKitManager = solanaKitManager
        self.moneroNodeManager = moneroNodeManager
        self.zanoNodeManager = zanoNodeManager
        self.zcashNodeManager = zcashNodeManager

        walletManager.activeWalletDataUpdatedObservable
            .observeOn(SerialDispatchQueueScheduler(qos: .userInitiated))
            .subscribe(onNext: { [weak self] walletData in
                self?.initAdapters(wallets: walletData.wallets, account: walletData.account, childWalletId: walletData.childWalletId)
            })
            .disposed(by: disposeBag)

        for blockchain in evmBlockchainManager.allBlockchains {
            if let manager = try? evmBlockchainManager.evmKitManager(blockchainType: blockchain.type) {
                subscribe(disposeBag, manager.evmKitUpdatedObservable) { [weak self] in self?.handleUpdatedEvmKit(blockchainType: blockchain.type) }
            }
        }
        subscribe(disposeBag, btcBlockchainManager.restoreModeUpdatedObservable) { [weak self] in self?.handleUpdatedRestoreMode(blockchainType: $0) }
        subscribe(disposeBag, moneroNodeManager.nodeObservable) { [weak self] in self?.recreateAdapter(blockchainType: $0) }
        subscribe(disposeBag, zanoNodeManager.nodeObservable) { [weak self] in self?.recreateAdapter(blockchainType: $0) }
        subscribe(disposeBag, zcashNodeManager.nodeObservable) { [weak self] in self?.handleZcashEndpointChange(blockchainType: $0) }
        subscribe(disposeBag, tronKitManager.tronKitUpdatedObservable) { [weak self] in self?.handleUpdatedEvmKit(blockchainType: .tron) }
        subscribe(disposeBag, solanaKitManager.kitStoppedObservable) { [weak self] in self?.recreateAdapter(blockchainType: .solana) }
    }

    private func initAdapters(wallets: [Wallet], account: Account?, childWalletId: String?) {
        initAdaptersQueue.async {
            self._initAdapters(wallets: wallets, account: account, childWalletId: childWalletId)
        }
    }

    private func _initAdapters(wallets: [Wallet], account: Account?, childWalletId: String?) {
        var newAdapterMap = queue.sync { _adapterData.adapterMap }
        let previousContext = queue.sync { (accountId: _adapterData.account?.id, childWalletId: _adapterData.childWalletId) }
        let nextContext = (accountId: account?.id, childWalletId: childWalletId)

        if previousContext.accountId != nextContext.accountId || previousContext.childWalletId != nextContext.childWalletId {
            for adapter in newAdapterMap.values {
                adapter.stop()
            }
            newAdapterMap = [:]
            src20SyncManager = nil
        }

        for wallet in wallets {
            guard newAdapterMap[wallet] == nil else {
                continue
            }
            if let adapter = adapterFactory.adapter(wallet: wallet) {
                if wallet.token.blockchain.type == .safe4, wallet.token.type == .native {
                    src20SyncManager = SRC20SyncManager(wallet: wallet, adapter: adapter)
                }
                newAdapterMap[wallet] = adapter
                adapter.start()
            }
        }

        var removedAdapters = [IAdapter]()

        for wallet in Array(newAdapterMap.keys) {
            guard !wallets.contains(wallet), let adapter = newAdapterMap.removeValue(forKey: wallet) else {
                continue
            }

            removedAdapters.append(adapter)
        }

        queue.async {
            let newAdapterData = AdapterData(adapterMap: newAdapterMap, account: account, childWalletId: childWalletId)
            self._adapterData = newAdapterData
            self.adapterDataReadyRelay.accept(newAdapterData)
        }

        for adapter in removedAdapters {
            adapter.stop()
        }
    }

    private func handleUpdatedEvmKit(blockchainType: BlockchainType) {
        let wallets = queue.sync { _adapterData.adapterMap.keys }
        refreshAdapters(wallets: wallets.filter { $0.token.blockchainType == blockchainType })
    }

    private func handleUpdatedRestoreMode(blockchainType: BlockchainType) {
        let wallets = queue.sync { _adapterData.adapterMap.keys }

        refreshAdapters(wallets: wallets.filter {
            $0.token.blockchain.type == blockchainType && $0.account.origin == .restored
        })
    }

    // Zcash changes the lightwalletd endpoint in place (synchronizer.switchTo), not by recreating the
    // adapter over the same local DB (which would report synced from cache). switchTo validates the
    // server and throws on failure; on failure we revert the stored selection to the endpoint actually
    // applied so the UI stays in sync with reality.
    private func handleZcashEndpointChange(blockchainType: BlockchainType) {
        guard blockchainType == .zcash else { return }

        let endpoint = ZcashAdapter.endpoint(url: zcashNodeManager.node(blockchainType: .zcash).url)

        let adapters = queue.sync {
            _adapterData.adapterMap.compactMap { wallet, adapter in
                wallet.token.blockchainType == .zcash ? adapter as? ZcashAdapter : nil
            }
        }

        guard !adapters.isEmpty else { return }

        Task { [weak self] in
            for adapter in adapters {
                do {
                    try await adapter.switchEndpoint(endpoint)
                } catch {
                    self?.revertZcashSelection(to: adapter)
                }
            }
        }
    }
    private func handleUpdatedMoneroNode(blockchainType: BlockchainType) {
        let wallets = queue.sync { _adapterData.adapterMap.keys }

        refreshAdapters(wallets: wallets.filter {
            $0.token.blockchain.type == blockchainType
        })
    }

    private func revertZcashSelection(to adapter: ZcashAdapter) {
        guard let appliedURL = adapter.currentEndpointURL,
              let node = zcashNodeManager.allNodes(blockchainType: .zcash).first(where: { $0.url == appliedURL })
        else {
            return
        }

        zcashNodeManager.setCurrent(node: node, blockchainType: .zcash)
    }

    private func refreshAdapters(wallets: [Wallet]) {
        guard !wallets.isEmpty else {
            return
        }

        if wallets.contains(where: { $0.token.blockchain.type == .safe4 }) {
            src20SyncManager = nil
        }

        queue.sync {
            for wallet in wallets {
                _adapterData.adapterMap[wallet]?.stop()
                _adapterData.adapterMap[wallet] = nil
            }
        }

        let activeWalletData = walletManager.activeWalletData
        initAdapters(wallets: activeWalletData.wallets, account: activeWalletData.account, childWalletId: activeWalletData.childWalletId)
    }
}

extension AdapterManager {
    var adapterData: AdapterData {
        queue.sync { _adapterData }
    }

    var adapterDataReadyObservable: Observable<AdapterData> {
        adapterDataReadyRelay.asObservable()
    }

    func adapter(for wallet: Wallet) -> IAdapter? {
        queue.sync { _adapterData.adapterMap[wallet] }
    }

    func adapter(for token: Token) -> IAdapter? {
        queue.sync {
            guard let wallet = walletManager.activeWallets.first(where: { $0.token == token }) else {
                return nil
            }

            return _adapterData.adapterMap[wallet]
        }
    }

    public func balanceAdapter(for wallet: Wallet) -> IBalanceAdapter? {
        queue.sync { _adapterData.adapterMap[wallet] as? IBalanceAdapter }
    }

    public func depositAdapter(for wallet: Wallet) -> IDepositAdapter? {
        queue.sync { _adapterData.adapterMap[wallet] as? IDepositAdapter }
    }

    func recreateAdapter(blockchainType: BlockchainType) {
        Task {
            if blockchainType == .zano {
                self.zanoKitManager.recreateKit()
            }

            let wallets = queue.sync { _adapterData.adapterMap.keys }

            refreshAdapters(wallets: wallets.filter {
                $0.token.blockchain.type == blockchainType
            })
        }
    }

    func validateZcashEndpoint(_ url: URL) async throws {
        let endpoint = ZcashAdapter.endpoint(url: url)

        let adapter = queue.sync {
            _adapterData.adapterMap.compactMap { wallet, adapter in
                wallet.token.blockchainType == .zcash ? adapter as? ZcashAdapter : nil
            }.first
        }

        guard let adapter else {
            throw ZcashEndpointValidationError.noActiveAdapter
        }

        guard await adapter.isEndpointAvailable(endpoint) else {
            throw ZcashEndpointValidationError.unavailable
        }
    }

    func refresh() {
        DispatchQueue.global(qos: .background).async {
            for (_, adapter) in self._adapterData.adapterMap {
                adapter.refresh()
            }

            self.tonKitManager.tonKit?.sync()
            self.stellarKitManager.stellarKit?.sync()
            self.zanoKitManager.kit?.refresh()
            self.solanaKitManager.solanaKit?.refresh()
        }
    }

    func refresh(wallet: Wallet) {
        DispatchQueue.global(qos: .background).async {
            if let adapter = self._adapterData.adapterMap[wallet] {
                adapter.refresh()
            } else if wallet.token.blockchainType == .ton {
                self.tonKitManager.tonKit?.sync()
            } else if wallet.token.blockchainType == .stellar {
                self.stellarKitManager.stellarKit?.sync()
            } else if wallet.token.blockchainType == .solana {
                self.solanaKitManager.solanaKit?.refresh()
            } else if wallet.token.blockchainType == .monero {
                (self._adapterData.adapterMap[wallet] as? MoneroAdapter)?.restart()
            } else if wallet.token.blockchainType == .zano {
                self.zanoKitManager.kit?.restart()
            }
        }
    }

    func preloadAdapters() {
        let activeWalletData = walletManager.activeWalletData
        initAdapters(wallets: activeWalletData.wallets, account: activeWalletData.account, childWalletId: activeWalletData.childWalletId)
    }
}

extension AdapterManager {
    struct AdapterData {
        var adapterMap: [Wallet: IAdapter]
        let account: Account?
        let childWalletId: String?
    }
}
