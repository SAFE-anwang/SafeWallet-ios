import Foundation
import MarketKit
import RxRelay
import RxSwift

private enum ZcashEndpointValidationError: LocalizedError {
    case noActiveAdapter
    case unavailable
    case sendInProgress

    var errorDescription: String? {
        switch self {
        case .noActiveAdapter: return "No active Zcash adapter"
        case .unavailable: return "Zcash endpoint is unavailable"
        case .sendInProgress: return "send.confirmation.sending".localized
        }
    }
}

public class AdapterManager {
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
    private let thorChainKitManager: ThorChainKitManager
    private let mayaChainKitManager: ThorChainKitManager

    private let adapterDataReadyRelay = PublishRelay<AdapterData>()

    private let queue = DispatchQueue(label: "\(AppConfig.label).adapter_manager", qos: .userInitiated)
    private let initAdaptersQueue = DispatchQueue(label: "\(AppConfig.label).adapter_manager.init_adapters", qos: .userInitiated)
    private var _adapterData = AdapterData(adapterMap: [:], account: nil, childWalletId: nil)
    private(set) var src20SyncManager: SRC20SyncManager?
    private var subscribedEvmKitManagers = [BlockchainType: ObjectIdentifier]()

    init(adapterFactory: AdapterFactory, walletManager: WalletManager, evmBlockchainManager: EvmBlockchainManager,
         tronKitManager: TronKitManager, tonKitManager: TonKitManager, stellarKitManager: StellarKitManager, zanoKitManager: ZanoKitManager, solanaKitManager: SolanaKitManager,
         btcBlockchainManager: BtcBlockchainManager, moneroNodeManager: MoneroNodeManager, zanoNodeManager: ZanoNodeManager, zcashNodeManager: ZcashNodeManager, thorChainKitManager: ThorChainKitManager, mayaChainKitManager: ThorChainKitManager)
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
        self.thorChainKitManager = thorChainKitManager
        self.mayaChainKitManager = mayaChainKitManager

        walletManager.activeWalletDataUpdatedObservable
            .observeOn(SerialDispatchQueueScheduler(qos: .userInitiated))
            .subscribe(onNext: { [weak self] walletData in
                self?.initAdapters(wallets: walletData.wallets, account: walletData.account, childWalletId: walletData.childWalletId)
            })
            .disposed(by: disposeBag)

        for blockchain in evmBlockchainManager.allBlockchains {
            subscribeEvmKitManager(blockchainType: blockchain.type)
        }
        subscribe(disposeBag, btcBlockchainManager.restoreModeUpdatedObservable) { [weak self] in self?.handleUpdatedRestoreMode(blockchainType: $0) }
        subscribe(disposeBag, moneroNodeManager.nodeObservable) { [weak self] in self?.recreateAdapter(blockchainType: $0) }
        subscribe(disposeBag, zanoNodeManager.nodeObservable) { [weak self] in self?.recreateAdapter(blockchainType: $0) }
        subscribe(disposeBag, zcashNodeManager.nodeObservable) { [weak self] in self?.handleZcashEndpointChange(blockchainType: $0) }
        subscribe(disposeBag, thorChainKitManager.kitUpdatedObservable) { [weak self] in self?.recreateAdapter(blockchainType: .thorChain) }
        subscribe(disposeBag, mayaChainKitManager.kitUpdatedObservable) { [weak self] in self?.recreateAdapter(blockchainType: .mayaChain) }
        subscribe(disposeBag, tronKitManager.tronKitUpdatedObservable) { [weak self] in self?.handleUpdatedEvmKit(blockchainType: .tron) }
        subscribe(disposeBag, solanaKitManager.kitStoppedObservable) { [weak self] in self?.recreateAdapter(blockchainType: .solana) }
    }

    private func subscribeEvmKitManager(blockchainType: BlockchainType) {
        guard let manager = try? evmBlockchainManager.evmKitManager(blockchainType: blockchainType) else {
            return
        }

        let identifier = ObjectIdentifier(manager)
        guard subscribedEvmKitManagers[blockchainType] != identifier else {
            return
        }

        subscribedEvmKitManagers[blockchainType] = identifier
        subscribe(disposeBag, manager.evmKitUpdatedObservable) { [weak self] in self?.handleUpdatedEvmKit(blockchainType: blockchainType) }
    }

    private func initAdapters(wallets: [Wallet], account: Account?, childWalletId: String?, completion: (() -> Void)? = nil) {
        initAdaptersQueue.async {
            self._initAdapters(wallets: wallets, account: account, childWalletId: childWalletId, completion: completion)
        }
    }

    private func _initAdapters(wallets: [Wallet], account: Account?, childWalletId: String?, completion: (() -> Void)? = nil) {
        var newAdapterMap = queue.sync { _adapterData.adapterMap }
        let previousContext = queue.sync { (accountId: _adapterData.account?.id, childWalletId: _adapterData.childWalletId) }
        let nextContext = (accountId: account?.id, childWalletId: childWalletId)

        if previousContext.accountId != nextContext.accountId || previousContext.childWalletId != nextContext.childWalletId {
            for adapter in newAdapterMap.values {
                adapter.stop()
            }
            newAdapterMap = [:]
            cancelSafe4SyncManager()
        }

        for wallet in wallets {
            guard newAdapterMap[wallet] == nil else {
                continue
            }
            if let adapter = adapterFactory.adapter(wallet: wallet) {
                if wallet.token.blockchain.type == .safe4, wallet.token.type == .native {
                    src20SyncManager?.cancel()
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
            completion?()
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

        let requestedURL = zcashNodeManager.node(blockchainType: .zcash).url

        Task { [weak self] in
            for adapter in adapters {
                do {
                    try await adapter.switchEndpoint(endpoint)
                } catch {
                    self?.revertZcashSelection(to: adapter, failedURL: requestedURL)
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

    private func revertZcashSelection(to adapter: ZcashAdapter, failedURL: URL) {
        // revert only while the failed target is still the persisted choice —
        // a newer user selection must not be clobbered by an older failure
        guard zcashNodeManager.node(blockchainType: .zcash).url == failedURL else {
            return
        }

        guard let appliedURL = adapter.currentEndpointURL,
              let node = zcashNodeManager.allNodes(blockchainType: .zcash).first(where: { $0.url == appliedURL })
        else {
            return
        }

        zcashNodeManager.setCurrent(node: node, blockchainType: .zcash)
    }

    private func refreshAdapters(wallets: [Wallet], completion: (() -> Void)? = nil) {
        guard !wallets.isEmpty else {
            completion?()
            return
        }

        if wallets.contains(where: { $0.token.blockchain.type == .safe4 }) {
            cancelSafe4SyncManager()
        }

        queue.sync {
            for wallet in wallets {
                _adapterData.adapterMap[wallet]?.stop()
                _adapterData.adapterMap[wallet] = nil
            }
        }

        let activeWalletData = walletManager.activeWalletData
        initAdapters(
            wallets: activeWalletData.wallets,
            account: activeWalletData.account,
            childWalletId: activeWalletData.childWalletId,
            completion: completion
        )
    }
}

extension AdapterManager {
    var adapterData: AdapterData {
        queue.sync { _adapterData }
    }

    var adapterDataReadyObservable: Observable<AdapterData> {
        adapterDataReadyRelay.asObservable()
    }

    public func adapter(for wallet: Wallet) -> IAdapter? {
        queue.sync { _adapterData.adapterMap[wallet] }
    }

    // Re-emits the current adapter data so consumers (e.g. transaction pools) rebuild against
    // adapters whose internal scope changed without being recreated - such as a Monero
    // account switch, which requires no kit restart.
    func reloadAdapterData() {
        queue.async {
            self.adapterDataReadyRelay.accept(self._adapterData)
        }
    }

    public func adapter(for token: Token) -> IAdapter? {
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

    // Re-runs adapter creation for active wallets that don't have an adapter yet
    // (e.g. Monero, deferred until the fastest node was resolved).
    func initMissingAdapters() {
        let activeWalletData = walletManager.activeWalletData
        initAdapters(
            wallets: activeWalletData.wallets,
            account: activeWalletData.account,
            childWalletId: activeWalletData.childWalletId
        )
    }

    func recreateAdapter(blockchainType: BlockchainType) {
        Task {
            await recreateAdapterAndWait(blockchainType: blockchainType)
        }
    }

    func recreateAdapterAndWait(blockchainType: BlockchainType) async {
        await withCheckedContinuation { continuation in
            if blockchainType == .zano {
                self.zanoKitManager.recreateKit()
            }

            let wallets = queue.sync { _adapterData.adapterMap.keys }
            refreshAdapters(wallets: wallets.filter {
                $0.token.blockchain.type == blockchainType
            }) { [weak self] in
                self?.subscribeEvmKitManager(blockchainType: blockchainType)
                continuation.resume()
            }
        }
    }

    func cancelSafe4SyncManager() {
        src20SyncManager?.cancel()
        src20SyncManager = nil
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

        // switching reconfigures the synchronizer under a live broadcast; background-finishing
        // work is bounded (local proving + 30s gRPC timeout per tx), so the refusal is short-lived.
        // a migration is an ordinary send, so it holds the same "zcash-send" critical section.
        let busy = await MainActor.run { Core.shared.backgroundTaskManager.isCriticalActive }
        guard !busy else {
            throw ZcashEndpointValidationError.sendInProgress
        }

        guard await adapter.isEndpointAvailable(endpoint) else {
            throw ZcashEndpointValidationError.unavailable
        }
    }

    func refresh() {
        let adapters = queue.sync { Array(_adapterData.adapterMap.values) }

        DispatchQueue.global(qos: .background).async {
            for adapter in adapters {
                adapter.refresh()
            }

            self.tonKitManager.tonKit?.sync()
            self.stellarKitManager.stellarKit?.sync()
            self.zanoKitManager.kit?.refresh()
            self.solanaKitManager.solanaKit?.refresh()
        }
    }

    func refresh(wallet: Wallet) {
        let adapter = queue.sync { _adapterData.adapterMap[wallet] }

        DispatchQueue.global(qos: .background).async {
            if let adapter {
                adapter.refresh()
            } else if wallet.token.blockchainType == .ton {
                self.tonKitManager.tonKit?.sync()
            } else if wallet.token.blockchainType == .stellar {
                self.stellarKitManager.stellarKit?.sync()
            } else if wallet.token.blockchainType == .solana {
                self.solanaKitManager.solanaKit?.refresh()
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
