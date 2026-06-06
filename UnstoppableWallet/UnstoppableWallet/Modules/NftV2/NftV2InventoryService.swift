import Foundation
import Combine
import EvmKit
import MarketKit
import RxRelay
import RxSwift
import UIKit

final class NftV2InventoryService {
    private static let fullSyncThrottleInterval: TimeInterval = 60
    private static let backgroundReconcileThrottleInterval: TimeInterval = 5 * 60
    private static let syncMaxConcurrent = 2
    private static let capabilityProbeAddress = "0x0000000000000000000000000000000000000001"
    private static let sendCapabilityProbeDelayNanoseconds: UInt64 = 300_000_000
    private static let sendCapabilityProbeAttempts = 6

    private let accountManager: AccountManager
    private let addressResolver: NftV2AddressResolver
    private let nftAdapterManager: NftAdapterManager
    private let nftMetadataManager: NftMetadataManager
    private let providers: [NftV2Chain: INftV2InventoryProvider]
    private let marketProvider: NftV2MarketProvider
    private let favoritesStore: NftV2FavoritesStore
    private let cacheStore: NftV2SnapshotCacheStore
    private let walletManager: WalletManager
    private let transactionAdapterManager: TransactionAdapterManager
    private let pendingTransferStore: NftV2PendingTransferStore
    private let disposeBag = DisposeBag()
    private var cancellables = Set<AnyCancellable>()
    private var adapterDisposeBag = DisposeBag()
    private let queue = DispatchQueue(label: "\(AppConfig.label).nft_v2_inventory_service", qos: .userInitiated)
    private let snapshotRelay: BehaviorRelay<NftV2Snapshot>
    private let chainUpdateRelay = PublishRelay<NftV2ChainUpdate>()
    private var currentAccountIdValue: String?
    private var chainStateMap = [NftV2Chain: NftV2ChainState]()
    private var syncingChains = Set<NftV2Chain>()
    private var queuedFullSyncChains = Set<NftV2Chain>()
    private var forcedFullSyncChains = Set<NftV2Chain>()
    private var chainSyncDisposableMap = [NftV2Chain: Disposable]()
    private var lastFullSyncTimestampByKey = [String: TimeInterval]()
    private var lastBackgroundReconcileTimestampByKey = [String: TimeInterval]()
    private var syncGeneration = 0

    init(
        accountManager: AccountManager,
        addressResolver: NftV2AddressResolver,
        nftAdapterManager: NftAdapterManager,
        nftMetadataManager: NftMetadataManager,
        providers: [NftV2Chain: INftV2InventoryProvider],
        marketProvider: NftV2MarketProvider,
        favoritesStore: NftV2FavoritesStore,
        cacheStore: NftV2SnapshotCacheStore,
        walletManager: WalletManager,
        transactionAdapterManager: TransactionAdapterManager,
        pendingTransferStore: NftV2PendingTransferStore
    ) {
        let emptySnapshot = Self.emptySnapshot(marketProvider: marketProvider)
        snapshotRelay = BehaviorRelay(value: emptySnapshot)
        self.accountManager = accountManager
        self.addressResolver = addressResolver
        self.nftAdapterManager = nftAdapterManager
        self.nftMetadataManager = nftMetadataManager
        self.providers = providers
        self.marketProvider = marketProvider
        self.favoritesStore = favoritesStore
        self.cacheStore = cacheStore
        self.walletManager = walletManager
        self.transactionAdapterManager = transactionAdapterManager
        self.pendingTransferStore = pendingTransferStore

        bindAccountChanges()
        bindAdapterChanges()
        bindMetadataChanges()
        bindProviderChanges()

        queue.async { [weak self] in
            self?.handleActiveAccountChanged(account: accountManager.activeAccount)
        }
    }

    func loadSnapshotSingle() -> Single<NftV2Snapshot> {
        snapshotRelay.asObservable()
            .take(1)
            .asSingle()
    }

    func snapshotObservable() -> Observable<NftV2Snapshot> {
        snapshotRelay.asObservable()
    }

    func chainUpdatesObservable() -> Observable<NftV2ChainUpdate> {
        chainUpdateRelay.asObservable()
    }

    func refresh() {
        queue.async {
            self.performRefresh(force: true)
        }
    }

    func toggleFavorite(collectionId: String) {
        favoritesStore.toggle(id: collectionId)
    }

    func isFavorite(collectionId: String) -> Bool {
        favoritesStore.isFavorite(id: collectionId)
    }

    func syncFavorites() {
        favoritesStore.syncFavorites()
    }

    func sendController(
        asset: NftV2Asset,
        onSendSuccess: @escaping (Data, Int) -> Void,
        onSendFailed: @escaping (String) -> Void
    ) -> UIViewController? {
        NftV2SendModule.viewController(
            asset: asset,
            displayMetadata: SendNftModule.DisplayMetadata(
                nftUid: asset.nftUid,
                name: asset.name,
                previewImageUrl: asset.imageUrl
            ),
            onSendSuccess: onSendSuccess,
            onSendFailed: onSendFailed
        )
    }

    func legacyController() -> UIViewController {
        NftV2Module.legacyViewController()
    }

    var activeAccountId: String? {
        accountManager.activeAccount?.id
    }

    var activeAccountIdPublisher: AnyPublisher<String?, Never> {
        accountManager.activeAccountPublisher
            .map { $0?.id }
            .eraseToAnyPublisher()
    }

    var currentSnapshot: NftV2Snapshot {
        snapshotRelay.value
    }

    func nftRecordsUpdatedObservable() -> Observable<Void> {
        chainUpdateRelay.map { _ in () }
    }

    func transactionRecordsObservable() -> Observable<(NftV2Chain, [TransactionRecord], Int?)> {
        let updates = transactionAdapterManager.adaptersReadyObservable
            .startWith(())
            .map { [weak self] _ -> Observable<(NftV2Chain, [TransactionRecord], Int?)> in
                guard let self, let account = self.accountManager.activeAccount else {
                    return .empty()
                }

                let observables: [Observable<(NftV2Chain, [TransactionRecord], Int?)>] = NftV2Chain.allCases.compactMap { chain in
                    guard let adapter = self.transactionAdapter(chain: chain, account: account) else {
                        return nil
                    }

                    let recordsObservable = adapter.transactionsObservable(token: nil, filter: .all, address: nil)
                        .share(replay: 1, scope: .whileConnected)

                    let transactionUpdates = recordsObservable
                        .map { (chain, $0, adapter.lastBlockInfo?.height) }
                    let blockUpdates = adapter.lastBlockUpdatedObservable
                        .withLatestFrom(recordsObservable) { _, records in
                            (chain, records, adapter.lastBlockInfo?.height)
                        }

                    return .merge(transactionUpdates, blockUpdates)
                }

                if observables.isEmpty {
                    return .empty()
                }

                return .merge(observables)
            }

        return updates.switchLatest()
    }

    private func bindAccountChanges() {
        accountManager.activeAccountPublisher
            .sink { [weak self] account in
                self?.queue.async {
                    self?.handleActiveAccountChanged(account: account)
                }
            }
            .store(in: &cancellables)
    }

    private func bindAdapterChanges() {
        nftAdapterManager.adaptersUpdatedObservable
            .observeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .subscribe(onNext: { [weak self] adapterMap in
                self?.handleAdaptersUpdated(adapterMap: adapterMap)
            })
            .disposed(by: disposeBag)
    }

    private func bindMetadataChanges() {
        nftMetadataManager.addressMetadataObservable
            .observeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .subscribe(onNext: { [weak self] nftKey, _ in
                self?.handleMetadataUpdated(nftKey: nftKey)
            })
            .disposed(by: disposeBag)
    }

    private func bindProviderChanges() {
        for provider in providers.values {
            provider.updatesObservable
                .observeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
                .subscribe(onNext: { [weak self] update in
                    self?.handleProviderUpdated(update: update)
                })
                .disposed(by: disposeBag)
        }
    }

    private func handleActiveAccountChanged(account: Account?) {
        syncGeneration += 1
        currentAccountIdValue = account?.id
        adapterDisposeBag = DisposeBag()
        chainSyncDisposableMap.values.forEach { $0.dispose() }
        chainSyncDisposableMap.removeAll()
        syncingChains.removeAll()
        queuedFullSyncChains.removeAll()
        forcedFullSyncChains.removeAll()
        lastFullSyncTimestampByKey.removeAll()
        lastBackgroundReconcileTimestampByKey.removeAll()

        let snapshot = buildInitialSnapshot(account: account)
        chainStateMap = Dictionary(uniqueKeysWithValues: snapshot.chainStates.map { ($0.chain, $0) })
        snapshotRelay.accept(snapshot)

        guard let account else {
            return
        }

        subscribeToAdapterRecords(adapterMap: nftAdapterManager.adapterMap, accountId: account.id)
        applyLocalPayloads(account: account)
        enqueueInitialDiscoverySyncs(account: account)
    }

    private func handleAdaptersUpdated(adapterMap: [NftKey: INftAdapter]) {
        queue.async {
            guard let account = self.accountManager.activeAccount,
                  account.id == self.currentAccountIdValue
            else {
                return
            }

            self.subscribeToAdapterRecords(adapterMap: adapterMap, accountId: account.id)
            self.applyLocalPayloads(account: account)
            self.enqueueInitialDiscoverySyncs(account: account)
        }
    }

    private func subscribeToAdapterRecords(adapterMap: [NftKey: INftAdapter], accountId: String) {
        adapterDisposeBag = DisposeBag()

        for (nftKey, adapter) in adapterMap where nftKey.account.id == accountId {
            adapter.nftRecordsObservable
                .observeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
                .subscribe(onNext: { [weak self] _ in
                    self?.handleAdapterRecordsUpdated(nftKey: nftKey)
                })
                .disposed(by: adapterDisposeBag)
        }
    }

    private func handleAdapterRecordsUpdated(nftKey: NftKey) {
        queue.async {
            guard nftKey.account.id == self.currentAccountIdValue,
                  let account = self.accountManager.activeAccount,
                  account.id == nftKey.account.id,
                  let chain = self.chain(blockchainType: nftKey.blockchainType)
            else {
                return
            }

            self.applyLocalPayload(chain: chain, account: account)
            self.enqueueBackgroundReconcileIfNeeded(chain: chain, account: account)
        }
    }

    private func handleMetadataUpdated(nftKey: NftKey) {
        queue.async {
            guard nftKey.account.id == self.currentAccountIdValue,
                  let account = self.accountManager.activeAccount,
                  account.id == nftKey.account.id,
                  let chain = self.chain(blockchainType: nftKey.blockchainType)
            else {
                return
            }

            self.applyLocalPayload(chain: chain, account: account)
        }
    }

    private func handleProviderUpdated(update: NftV2ProviderUpdate) {
        queue.async {
            guard let account = self.accountManager.activeAccount,
                  account.id == self.currentAccountIdValue,
                  account.id == update.accountId,
                  let context = self.addressResolver.addressContexts(account: account)[update.chain],
                  context.address.lowercased() == update.address
            else {
                return
            }

            self.applyLocalPayload(chain: update.chain, account: account)
        }
    }

    private func performRefresh(force: Bool) {
        guard let account = accountManager.activeAccount,
              account.id == currentAccountIdValue
        else {
            return
        }

        nftAdapterManager.refresh()
        enqueueFullSyncs(chains: Self.syncPriorityChains, account: account, force: force)
    }

    private func enqueueInitialDiscoverySyncs(account: Account) {
        let cachedPayloads = cacheStore.load(accountId: account.id)
        let undiscoveredChains = NftV2Chain.allCases.filter { chain in
            guard let provider = providers[chain] else {
                return false
            }

            guard case .available = provider.availability else {
                return false
            }

            if let cachedPayload = cachedPayloads[chain], cachedPayload.hasDiscoveredInventory {
                return false
            }

            return true
        }

        guard !undiscoveredChains.isEmpty else {
            return
        }

        let prioritized = Self.initialDiscoveryPriorityChains.filter { undiscoveredChains.contains($0) }
        let remaining = undiscoveredChains.filter { !prioritized.contains($0) }

        if !prioritized.isEmpty {
            enqueueFullSyncs(chains: prioritized, account: account, force: false)
        }

        if !remaining.isEmpty {
            enqueueFullSyncs(chains: remaining, account: account, force: false)
        }
    }

    private func enqueueBackgroundReconcileIfNeeded(chain: NftV2Chain, account: Account) {
        let throttleKey = "\(account.id)|\(chain.rawValue)"
        let now = Date().timeIntervalSince1970

        if let timestamp = lastBackgroundReconcileTimestampByKey[throttleKey],
           now - timestamp < Self.backgroundReconcileThrottleInterval
        {
            return
        }

        lastBackgroundReconcileTimestampByKey[throttleKey] = now
        enqueueFullSyncs(chains: [chain], account: account, force: false)
    }

    private func buildInitialSnapshot(account: Account?) -> NftV2Snapshot {
        guard let account else {
            return Self.emptySnapshot(marketProvider: marketProvider)
        }

        let contexts = addressResolver.addressContexts(account: account)
        let cachedPayloads = cacheStore.load(accountId: account.id)
        let chainStates = NftV2Chain.allCases.map { chain in
            initialChainState(account: account, chain: chain, context: contexts[chain], cachedPayload: cachedPayloads[chain])
        }

        return composeSnapshot(chainStates: chainStates)
    }

    private func applyLocalPayloads(account: Account) {
        for chain in NftV2Chain.allCases {
            applyLocalPayload(chain: chain, account: account)
        }
    }

    private func applyLocalPayload(chain: NftV2Chain, account: Account) {
        let contexts = addressResolver.addressContexts(account: account)
        guard let context = contexts[chain],
              let provider = providers[chain]
        else {
            return
        }

        switch provider.availability {
        case .available:
            guard let localPayload = provider.localPayload(address: context.address, account: account) else {
                return
            }

            let payload = mergedPayload(
                preferred: localPayload,
                fallback: currentSnapshot.chainStates.first(where: { $0.chain == chain })?.payload
            )
            let count = payload.collections.reduce(0) { $0 + $1.items.count }
            let refreshing = syncingChains.contains(chain)
            let status: NftV2ChainState.Status = refreshing ? .syncing(count: count) : .cached(count: count)
            let state = NftV2ChainState(
                chain: chain,
                address: context.address,
                market: marketProvider.primaryMarket(chain: chain),
                status: status,
                isRefreshing: refreshing,
                payload: payload
            )

            updateChainState(state)
        case let .degraded(reason):
            let state = NftV2ChainState(
                chain: chain,
                address: context.address,
                market: marketProvider.primaryMarket(chain: chain),
                status: .unavailable(reason: reason),
                isRefreshing: false
            )
            updateChainState(state)
        }
    }

    private func enqueueFullSyncs(chains: [NftV2Chain], account: Account, force: Bool) {
        for chain in chains {
            queuedFullSyncChains.insert(chain)
            if force {
                forcedFullSyncChains.insert(chain)
            }
        }

        drainFullSyncQueue(account: account)
    }

    private func drainFullSyncQueue(account: Account) {
        guard account.id == currentAccountIdValue else {
            return
        }

        let contexts = addressResolver.addressContexts(account: account)

        for chain in Self.syncPriorityChains {
            guard syncingChains.count < Self.syncMaxConcurrent else {
                break
            }
            guard queuedFullSyncChains.contains(chain) else {
                continue
            }
            guard let context = contexts[chain],
                  let provider = providers[chain],
                  provider.canLoad(address: context.address, account: account)
            else {
                continue
            }

            queuedFullSyncChains.remove(chain)
            let force = forcedFullSyncChains.remove(chain) != nil
            startFullSync(chain: chain, account: account, context: context, force: force)
        }
    }

    private func startFullSync(chain: NftV2Chain, account: Account, context: NftV2AddressContext, force: Bool) {
        let throttleKey = "\(account.id)|\(chain.rawValue)"
        let now = Date().timeIntervalSince1970

        if !force,
           let timestamp = lastFullSyncTimestampByKey[throttleKey],
           now - timestamp < Self.fullSyncThrottleInterval
        {
            return
        }

        lastFullSyncTimestampByKey[throttleKey] = now
        syncingChains.insert(chain)
        emitRefreshingState(chain: chain, context: context)

        let cachedPayloads = cacheStore.load(accountId: account.id)
        let generation = syncGeneration

        chainSyncDisposableMap[chain]?.dispose()
        chainSyncDisposableMap[chain] = syncedChainStateSingle(
            account: account,
            chain: chain,
            context: context,
            cachedPayload: cachedPayloads[chain]
        )
        .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
        .subscribe(onSuccess: { [weak self] state in
            self?.queue.async {
                self?.handleFullSyncCompleted(state: state, chain: chain, accountId: account.id, generation: generation)
            }
        }, onError: { [weak self] _ in
            self?.queue.async {
                self?.handleFullSyncFailed(chain: chain, accountId: account.id, generation: generation)
            }
        })
    }

    private func emitRefreshingState(chain: NftV2Chain, context: NftV2AddressContext) {
        let payload = chainStateMap[chain]?.payload
        let count = payload?.collections.reduce(0) { $0 + $1.items.count } ?? 0
        let state = NftV2ChainState(
            chain: chain,
            address: context.address,
            market: marketProvider.primaryMarket(chain: chain),
            status: .syncing(count: count),
            isRefreshing: true,
            payload: payload
        )

        updateChainState(state)
    }

    private func handleFullSyncCompleted(state: NftV2ChainState, chain: NftV2Chain, accountId: String, generation: Int) {
        guard generation == syncGeneration, accountId == currentAccountIdValue else {
            return
        }

        syncingChains.remove(chain)
        chainSyncDisposableMap[chain] = nil
        updateChainState(state)

        if let account = accountManager.activeAccount, account.id == accountId {
            drainFullSyncQueue(account: account)
        }
    }

    private func handleFullSyncFailed(chain: NftV2Chain, accountId: String, generation: Int) {
        guard generation == syncGeneration, accountId == currentAccountIdValue else {
            return
        }

        syncingChains.remove(chain)
        chainSyncDisposableMap[chain] = nil

        if let account = accountManager.activeAccount, account.id == accountId {
            drainFullSyncQueue(account: account)
        }
    }

    private func updateChainState(_ state: NftV2ChainState) {
        chainStateMap[state.chain] = state
        let orderedStates = NftV2Chain.allCases.compactMap { chainStateMap[$0] }
        snapshotRelay.accept(composeSnapshot(chainStates: orderedStates))
        chainUpdateRelay.accept(
            NftV2ChainUpdate(
                chainState: state,
                collections: state.payload?.collections.filter { $0.chain == state.chain } ?? []
            )
        )
    }

    private func chain(blockchainType: BlockchainType) -> NftV2Chain? {
        NftV2Chain.allCases.first { $0.blockchainType == blockchainType }
    }

    private static func emptySnapshot(marketProvider: NftV2MarketProvider) -> NftV2Snapshot {
        NftV2Snapshot(
            collections: [],
            chainStates: NftV2Chain.allCases.map { chain in
                NftV2ChainState(
                    chain: chain,
                    address: nil,
                    market: marketProvider.primaryMarket(chain: chain),
                    status: .inactive,
                    isRefreshing: false
                )
            }
        )
    }

    func pendingTransfers() -> [NftV2PendingTransferItem] {
        guard let account = accountManager.activeAccount else {
            return []
        }

        return pendingTransferStore.items(accountId: account.id).compactMap { item in
            guard let chain = NftV2Chain(rawValue: item.chain),
                  let nftUid = NftUid(uid: item.nftUid)
            else {
                return nil
            }

            let market = item.market.flatMap(NftV2Market.init(rawValue:))

            let asset = NftV2Asset(
                id: item.assetId,
                nftUid: nftUid,
                chain: chain,
                contractAddress: item.contractAddress,
                tokenId: item.tokenId,
                standard: item.standard,
                name: item.name,
                imageUrl: item.imageUrl,
                collectionName: item.collectionName,
                market: market,
                marketUrl: item.marketUrl,
                balance: item.balance,
                canSend: false,
                transferType: item.transferType.flatMap(NftV2TransferType.init(rawValue:)) ?? .unknown
            )

            return NftV2PendingTransferItem(
                id: item.id,
                chain: chain,
                collectionId: item.collectionId,
                collectionName: item.collectionName,
                asset: asset,
                amount: item.amount,
                transactionHash: item.transactionHash,
                explorerUrl: transactionAdapter(chain: chain, account: account)?.explorerUrl(transactionHash: item.transactionHash),
                submittedAt: Date(timeIntervalSince1970: item.submittedAt)
            )
        }
    }

    func savePendingTransfer(asset: NftV2Asset, collection: NftV2Collection, amount: Int, transactionHash: String) {
        guard let accountId = activeAccountId else {
            return
        }

        let item = NftV2PendingTransferStore.Item(
            accountId: accountId,
            chain: asset.chain.rawValue,
            collectionId: collection.id,
            collectionName: collection.name,
            assetId: asset.id,
            nftUid: asset.nftUid.uid,
            contractAddress: asset.contractAddress,
            tokenId: asset.tokenId,
            standard: asset.standard,
            name: asset.name,
            imageUrl: asset.imageUrl,
            market: asset.market?.rawValue,
            marketUrl: asset.marketUrl,
            balance: asset.balance,
            canSend: false,
            transferType: asset.transferType.rawValue,
            amount: max(amount, 1),
            transactionHash: transactionHash,
            submittedAt: Date().timeIntervalSince1970
        )

        pendingTransferStore.save(item)
    }

    func removePendingTransfer(chain: NftV2Chain, transactionHash: String) {
        guard let accountId = activeAccountId else {
            return
        }

        pendingTransferStore.remove(
            accountId: accountId,
            chain: chain.rawValue,
            transactionHash: transactionHash
        )
    }

    func initialSendCapability(asset: NftV2Asset) -> NftV2SendCapability {
        guard asset.canSend else {
            return .blocked(reason: .unavailable)
        }

        guard let account = accountManager.activeAccount, !account.watchAccount else {
            return .blocked(reason: .unavailable)
        }

        let chainState = snapshotChainState(chain: asset.chain)
        let ownedSnapshotAsset = snapshotAsset(asset: asset)

        guard let adapter = nftAdapterManager.adapter(nftKey: NftKey(account: account, blockchainType: asset.chain.blockchainType)) else {
            return chainState?.isRefreshing == true ? .checking : .blocked(reason: .unavailable)
        }

        if let record = adapter.nftRecord(nftUid: asset.nftUid),
           record.balance > 0,
           canBuildTransferData(adapter: adapter, record: record) {
            return .ready
        }

        let effectiveAsset = ownedSnapshotAsset ?? asset
        if effectiveAsset.balance > 0,
           canBuildTransferData(
               adapter: adapter,
               transferType: effectiveAsset.transferType,
               contractAddress: effectiveAsset.contractAddress,
               tokenId: effectiveAsset.tokenId,
               balance: effectiveAsset.balance
           )
        {
            return .ready
        }

        return chainState?.isRefreshing == true ? .checking : .blocked(reason: .unavailable)
    }

    func refreshSendCapability(asset: NftV2Asset) async -> NftV2SendCapability {
        let fastCapability = initialSendCapability(asset: asset)
        if fastCapability != .checking {
            return fastCapability
        }

        guard let account = accountManager.activeAccount, !account.watchAccount else {
            return .blocked(reason: .unavailable)
        }

        let nftKey = NftKey(account: account, blockchainType: asset.chain.blockchainType)
        guard let adapter = nftAdapterManager.adapter(nftKey: nftKey) else {
            return .blocked(reason: .unavailable)
        }

        adapter.sync()
        for _ in 0 ..< Self.sendCapabilityProbeAttempts {
            let refreshed = initialSendCapability(asset: asset)
            if refreshed != .checking {
                return refreshed
            }

            try? await Task.sleep(nanoseconds: Self.sendCapabilityProbeDelayNanoseconds)
        }

        let latest = initialSendCapability(asset: asset)
        return latest == .checking ? .blocked(reason: .unavailable) : latest
    }

    private func initialChainState(account: Account, chain: NftV2Chain, context: NftV2AddressContext?, cachedPayload: NftV2SnapshotCacheStore.CachedPayload?) -> NftV2ChainState {
        let market = marketProvider.primaryMarket(chain: chain)

        guard let context else {
            return NftV2ChainState(
                chain: chain,
                address: nil,
                market: market,
                status: .inactive,
                isRefreshing: false
            )
        }

        guard let provider = providers[chain] else {
            return NftV2ChainState(
                chain: chain,
                address: context.address,
                market: market,
                status: .unavailable(reason: "nft_v2.error.missing_provider".localized),
                isRefreshing: false
            )
        }

        switch provider.availability {
        case .available:
            if let cachedPayload {
                let count = cachedPayload.payload.collections.reduce(0) { $0 + $1.items.count }
                let hasLocalPayload = provider.localPayload(address: context.address, account: account) != nil
                return NftV2ChainState(
                    chain: chain,
                    address: context.address,
                    market: market,
                    status: .cached(count: count),
                    isRefreshing: !cachedPayload.hasDiscoveredInventory && !hasLocalPayload,
                    payload: cachedPayload.payload
                )
            }

            return NftV2ChainState(
                chain: chain,
                address: context.address,
                market: market,
                status: .syncing(count: 0),
                isRefreshing: true
            )
        case let .degraded(reason):
            return NftV2ChainState(
                chain: chain,
                address: context.address,
                market: market,
                status: .unavailable(reason: reason),
                isRefreshing: false
            )
        }
    }

    private func syncedChainStateSingle(
        account: Account,
        chain: NftV2Chain,
        context: NftV2AddressContext?,
        cachedPayload: NftV2SnapshotCacheStore.CachedPayload?
    ) -> Single<NftV2ChainState> {
        let market = marketProvider.primaryMarket(chain: chain)

        guard let context else {
            return .just(
                NftV2ChainState(
                    chain: chain,
                    address: nil,
                    market: market,
                    status: .inactive,
                    isRefreshing: false
                )
            )
        }

        guard let provider = providers[chain] else {
            return .just(
                NftV2ChainState(
                    chain: chain,
                    address: context.address,
                    market: market,
                    status: .unavailable(reason: "nft_v2.error.missing_provider".localized),
                    isRefreshing: false,
                    payload: cachedPayload?.payload
                )
            )
        }

        switch provider.availability {
        case .available:
            return provider.load(address: context.address, account: account)
                .map { payload in
                    let effectivePayload = self.mergedPayload(preferred: payload, fallback: cachedPayload?.payload)
                    self.cacheStore.save(
                        payload: effectivePayload,
                        accountId: account.id,
                        chain: chain,
                        address: context.address,
                        market: market
                    )

                    return NftV2ChainState(
                        chain: chain,
                        address: context.address,
                        market: market,
                        status: .synced(count: effectivePayload.collections.reduce(0) { $0 + $1.items.count }),
                        isRefreshing: false,
                        payload: effectivePayload
                    )
                }
                .catchErrorJustReturn(
                    NftV2ChainState(
                        chain: chain,
                        address: context.address,
                        market: market,
                        status: .failed(message: "nft_v2.error.load_inventory".localized),
                        isRefreshing: false,
                        payload: cachedPayload?.payload
                    )
                )
        case let .degraded(reason):
            return .just(
                NftV2ChainState(
                    chain: chain,
                    address: context.address,
                    market: market,
                    status: .unavailable(reason: reason),
                    isRefreshing: false,
                    payload: cachedPayload?.payload
                )
            )
        }
    }

    private func composeSnapshot(chainStates: [NftV2ChainState]) -> NftV2Snapshot {
        let collections = chainStates
            .compactMap(\.payload?.collections)
            .flatMap { $0 }
            .sorted { lhs, rhs in
                if favoritesStore.isFavorite(id: lhs.id) != favoritesStore.isFavorite(id: rhs.id) {
                    return favoritesStore.isFavorite(id: lhs.id)
                }

                if lhs.chain != rhs.chain {
                    return lhs.chain.sortIndex < rhs.chain.sortIndex
                }

                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

        return NftV2Snapshot(collections: collections, chainStates: chainStates)
    }

    private func snapshotChainState(chain: NftV2Chain) -> NftV2ChainState? {
        currentSnapshot.chainStates.first(where: { $0.chain == chain })
    }

    private func snapshotAsset(asset: NftV2Asset) -> NftV2Asset? {
        for collection in currentSnapshot.collections where collection.chain == asset.chain {
            if let matched = collection.items.first(where: { $0.id == asset.id }) {
                return matched
            }
        }

        return nil
    }

    private func mergedPayload(preferred: NftV2InventoryPayload, fallback: NftV2InventoryPayload?) -> NftV2InventoryPayload {
        guard let fallback else {
            return preferred
        }

        let fallbackCollectionMap = Dictionary(uniqueKeysWithValues: fallback.collections.map { ($0.id, $0) })
        let collections = preferred.collections.map { collection in
            guard let existing = fallbackCollectionMap[collection.id] else {
                return collection
            }

            return mergedCollection(preferred: collection, fallback: existing)
        }

        return NftV2InventoryPayload(
            collections: collections.sorted(by: collectionSort)
        )
    }

    private func mergedCollection(preferred: NftV2Collection, fallback: NftV2Collection) -> NftV2Collection {
        let fallbackAssetMap = Dictionary(uniqueKeysWithValues: fallback.items.map { ($0.id, $0) })
        let items = preferred.items.map { asset in
            guard let existing = fallbackAssetMap[asset.id] else {
                return asset
            }

            return mergedAsset(preferred: asset, fallback: existing)
        }

        return NftV2Collection(
            id: preferred.id,
            chain: preferred.chain,
            contractAddress: preferred.contractAddress,
            name: preferred.name,
            imageUrl: preferred.imageUrl ?? fallback.imageUrl,
            market: preferred.market ?? fallback.market,
            marketUrl: preferred.marketUrl ?? fallback.marketUrl,
            items: items.sorted(by: assetSort)
        )
    }

    private func mergedAsset(preferred: NftV2Asset, fallback: NftV2Asset) -> NftV2Asset {
        NftV2Asset(
            id: preferred.id,
            nftUid: preferred.nftUid,
            chain: preferred.chain,
            contractAddress: preferred.contractAddress,
            tokenId: preferred.tokenId,
            standard: preferred.standard,
            name: preferred.name,
            imageUrl: preferred.imageUrl ?? fallback.imageUrl,
            collectionName: preferred.collectionName,
            market: preferred.market ?? fallback.market,
            marketUrl: preferred.marketUrl ?? fallback.marketUrl,
            balance: preferred.balance,
            canSend: preferred.canSend || fallback.canSend,
            transferType: preferred.transferType == .unknown ? fallback.transferType : preferred.transferType
        )
    }

    private static func message(error: Error) -> String {
        let message = (error as NSError).localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "nft_v2.error.load_inventory".localized : message
    }

    private static var syncPriorityChains: [NftV2Chain] {
        let prioritized: [NftV2Chain] = [.ethereum, .binanceSmartChain]
        let remaining = NftV2Chain.allCases.filter { !prioritized.contains($0) }
        return prioritized + remaining
    }

    private static var initialDiscoveryPriorityChains: [NftV2Chain] {
        let prioritized: [NftV2Chain] = [.ethereum, .binanceSmartChain, .polygon]
        let remaining = NftV2Chain.allCases.filter { !prioritized.contains($0) }
        return prioritized + remaining
    }

    private func canBuildTransferData(adapter: INftAdapter, record: NftRecord) -> Bool {
        guard let evmRecord = record as? EvmNftRecord else {
            return false
        }

        switch evmRecord.type {
        case .eip721:
            return canBuildTransferData(
                adapter: adapter,
                transferType: .eip721,
                contractAddress: evmRecord.contractAddress,
                tokenId: evmRecord.tokenId,
                balance: evmRecord.balance
            )
        case .eip1155:
            return canBuildTransferData(
                adapter: adapter,
                transferType: .eip1155,
                contractAddress: evmRecord.contractAddress,
                tokenId: evmRecord.tokenId,
                balance: evmRecord.balance
            )
        }
    }

    private func canBuildTransferData(
        adapter: INftAdapter,
        transferType: NftV2TransferType,
        contractAddress: String,
        tokenId: String,
        balance: Int
    ) -> Bool {
        guard let probeAddress = try? EvmKit.Address(hex: Self.capabilityProbeAddress) else {
            return false
        }

        switch transferType {
        case .eip721:
            return adapter.transferEip721TransactionData(
                contractAddress: contractAddress,
                to: probeAddress,
                tokenId: tokenId
            ) != nil
        case .eip1155:
            let value = Decimal(max(1, balance))
            return adapter.transferEip1155TransactionData(
                contractAddress: contractAddress,
                to: probeAddress,
                tokenId: tokenId,
                value: value
            ) != nil
        case .unknown:
            return false
        }
    }

    private func assetSort(lhs: NftV2Asset, rhs: NftV2Asset) -> Bool {
        lhs.tokenId.localizedStandardCompare(rhs.tokenId) == .orderedAscending
    }

    private func collectionSort(lhs: NftV2Collection, rhs: NftV2Collection) -> Bool {
        lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private func transactionAdapter(chain: NftV2Chain, account: Account) -> ITransactionsAdapter? {
        guard let wallet = walletManager.activeWallets.first(where: {
            $0.account.id == account.id &&
                $0.token.blockchainType == chain.blockchainType &&
                $0.token.type.isNative
        }) else {
            return nil
        }

        return transactionAdapterManager.adapter(for: wallet.transactionSource)
    }
}

final class NftV2SnapshotCacheStore {
    struct CachedPayload {
        let payload: NftV2InventoryPayload
        let updatedAt: TimeInterval
        let hasDiscoveredInventory: Bool
    }

    private struct Cache: Codable {
        var items: [ChainCacheItem]
    }

    private struct ChainCacheItem: Codable {
        let chain: String
        let address: String?
        let market: String?
        let hasDiscoveredInventory: Bool
        let collections: [CollectionCache]
        let updatedAt: TimeInterval
    }

    private struct CollectionCache: Codable {
        let id: String
        let chain: String
        let contractAddress: String
        let name: String
        let imageUrl: String?
        let market: String?
        let marketUrl: String?
        let items: [AssetCache]
    }

    private struct AssetCache: Codable {
        let id: String
        let nftUid: String
        let chain: String
        let contractAddress: String
        let tokenId: String
        let standard: String
        let name: String
        let imageUrl: String?
        let collectionName: String
        let market: String?
        let marketUrl: String?
        let balance: Int
        let canSend: Bool
        let transferType: String?
    }

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "\(AppConfig.label).nft_v2_snapshot_cache_store")

    func load(accountId: String) -> [NftV2Chain: CachedPayload] {
        queue.sync {
            guard let cache = readCache(accountId: accountId) else {
                return [:]
            }

            var payloadByChain = [NftV2Chain: CachedPayload]()
            for item in cache.items {
                guard let chain = NftV2Chain(rawValue: item.chain) else {
                    continue
                }

                let collections = item.collections.compactMap(Self.collection(from:))
                payloadByChain[chain] = CachedPayload(
                    payload: NftV2InventoryPayload(collections: collections),
                    updatedAt: item.updatedAt,
                    hasDiscoveredInventory: item.hasDiscoveredInventory
                )
            }

            return payloadByChain
        }
    }

    func save(payload: NftV2InventoryPayload, accountId: String, chain: NftV2Chain, address: String?, market: NftV2Market?) {
        queue.sync {
            var cache = readCache(accountId: accountId) ?? Cache(items: [])

            let chainItem = ChainCacheItem(
                chain: chain.rawValue,
                address: address,
                market: market?.rawValue,
                hasDiscoveredInventory: true,
                collections: payload.collections.map(Self.collectionCache(from:)),
                updatedAt: Date().timeIntervalSince1970
            )

            if let index = cache.items.firstIndex(where: { $0.chain == chain.rawValue }) {
                cache.items[index] = chainItem
            } else {
                cache.items.append(chainItem)
            }

            write(cache: cache, accountId: accountId)
        }
    }

    private func fileUrl(accountId: String) -> URL? {
        guard let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }

        let dir = base.appendingPathComponent("nft_v2_cache", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        return dir.appendingPathComponent("snapshot_\(accountId).json")
    }

    private func readCache(accountId: String) -> Cache? {
        guard let url = fileUrl(accountId: accountId),
              let data = try? Data(contentsOf: url)
        else {
            return nil
        }

        return try? JSONDecoder().decode(Cache.self, from: data)
    }

    private func write(cache: Cache, accountId: String) {
        guard let url = fileUrl(accountId: accountId),
              let data = try? JSONEncoder().encode(cache)
        else {
            return
        }

        try? data.write(to: url, options: .atomic)
    }

    private static func collectionCache(from collection: NftV2Collection) -> CollectionCache {
        CollectionCache(
            id: collection.id,
            chain: collection.chain.rawValue,
            contractAddress: collection.contractAddress,
            name: collection.name,
            imageUrl: collection.imageUrl,
            market: collection.market?.rawValue,
            marketUrl: collection.marketUrl,
            items: collection.items.map(assetCache(from:))
        )
    }

    private static func assetCache(from asset: NftV2Asset) -> AssetCache {
        AssetCache(
            id: asset.id,
            nftUid: asset.nftUid.uid,
            chain: asset.chain.rawValue,
            contractAddress: asset.contractAddress,
            tokenId: asset.tokenId,
            standard: asset.standard,
            name: asset.name,
            imageUrl: asset.imageUrl,
            collectionName: asset.collectionName,
            market: asset.market?.rawValue,
            marketUrl: asset.marketUrl,
            balance: asset.balance,
            canSend: asset.canSend,
            transferType: asset.transferType.rawValue
        )
    }

    private static func collection(from cache: CollectionCache) -> NftV2Collection? {
        guard let chain = NftV2Chain(rawValue: cache.chain) else {
            return nil
        }

        let items = cache.items.compactMap(asset(from:))

        return NftV2Collection(
            id: cache.id,
            chain: chain,
            contractAddress: cache.contractAddress,
            name: cache.name,
            imageUrl: cache.imageUrl,
            market: cache.market.flatMap(NftV2Market.init(rawValue:)),
            marketUrl: cache.marketUrl,
            items: items
        )
    }

    private static func asset(from cache: AssetCache) -> NftV2Asset? {
        guard let chain = NftV2Chain(rawValue: cache.chain),
              let nftUid = NftUid(uid: cache.nftUid)
        else {
            return nil
        }

        return NftV2Asset(
            id: cache.id,
            nftUid: nftUid,
            chain: chain,
            contractAddress: cache.contractAddress,
            tokenId: cache.tokenId,
            standard: cache.standard,
            name: cache.name,
            imageUrl: cache.imageUrl,
            collectionName: cache.collectionName,
            market: cache.market.flatMap(NftV2Market.init(rawValue:)),
            marketUrl: cache.marketUrl,
            balance: cache.balance,
            canSend: cache.canSend,
            transferType: cache.transferType.flatMap(NftV2TransferType.init(rawValue:)) ?? .unknown
        )
    }
}
