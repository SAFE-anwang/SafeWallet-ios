import Foundation
import EvmKit
import BigInt
import RxRelay
import RxSwift
import UniswapKit

protocol INftV2InventoryProvider {
    var chain: NftV2Chain { get }
    var availability: NftV2ProviderAvailability { get }
    var updatesObservable: Observable<NftV2ProviderUpdate> { get }

    func canLoad(address: String, account: Account) -> Bool
    func localPayload(address: String, account: Account) -> NftV2InventoryPayload?
    func load(address: String, account: Account) -> Single<NftV2InventoryPayload>
}

extension INftV2InventoryProvider {
    var updatesObservable: Observable<NftV2ProviderUpdate> {
        .empty()
    }

    func canLoad(address _: String, account _: Account) -> Bool {
        true
    }

    func localPayload(address _: String, account _: Account) -> NftV2InventoryPayload? {
        nil
    }
}

enum NftV2ProviderAvailability {
    case available
    case degraded(reason: String)
}

struct NftV2InventoryPayload {
    let collections: [NftV2Collection]
}

private struct NftV2WalletInventoryItem {
    let record: NftRecord
    let assetMetadata: NftAssetShortMetadata?
    let onChainMetadata: NftV2OnChainAssetMetadata?
}

final class NftV2UnavailableInventoryProvider: INftV2InventoryProvider {
    let chain: NftV2Chain
    let availability: NftV2ProviderAvailability

    init(chain: NftV2Chain, reason: String) {
        self.chain = chain
        availability = .degraded(reason: reason)
    }

    func load(address _: String, account _: Account) -> Single<NftV2InventoryPayload> {
        .just(NftV2InventoryPayload(collections: []))
    }
}

final class NftV2OpenSeaInventoryProvider: INftV2InventoryProvider {
    let chain: NftV2Chain
    let availability: NftV2ProviderAvailability

    private let provider: OpenSeaNftProvider
    private let marketProvider: NftV2MarketProvider

    init(chain: NftV2Chain, provider: OpenSeaNftProvider, marketProvider: NftV2MarketProvider) {
        self.chain = chain
        self.provider = provider
        self.marketProvider = marketProvider

        if AppConfig.openSeaApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            availability = .degraded(reason: "nft_v2.error.missing_opensea_key".localized)
        } else {
            availability = .available
        }
    }

    func load(address: String, account: Account) -> Single<NftV2InventoryPayload> {
        provider.addressMetadataSingle(blockchainType: chain.blockchainType, address: address)
            .map { [chain, marketProvider] metadata -> NftV2InventoryPayload in
                let groupedAssets = Dictionary(grouping: metadata.assets, by: \.providerCollectionUid)

                let collections = groupedAssets.compactMap { providerUid, assets -> NftV2Collection? in
                    guard let firstAsset = assets.first else {
                        return nil
                    }

                    let collectionMetadata = metadata.collections.first { $0.providerUid == providerUid }
                    let market = marketProvider.primaryMarket(chain: chain)
                    let mappedAssets = assets.map { asset in
                        NftV2Asset(
                            id: asset.nftUid.uid,
                            nftUid: asset.nftUid,
                            chain: chain,
                            contractAddress: asset.nftUid.contractAddress,
                            tokenId: asset.nftUid.tokenId,
                            standard: "nft_v2.asset.standard".localized,
                            name: asset.displayName,
                            imageUrl: asset.previewImageUrl,
                            collectionName: collectionMetadata?.name ?? providerUid,
                            market: market,
                            marketUrl: marketProvider.assetUrl(chain: chain, contractAddress: asset.nftUid.contractAddress, tokenId: asset.nftUid.tokenId),
                            balance: 1,
                            canSend: !account.watchAccount,
                            transferType: .unknown
                        )
                    }
                    .sorted { $0.tokenId.localizedStandardCompare($1.tokenId) == .orderedAscending }

                    return NftV2Collection(
                        id: "\(chain.rawValue)-\(providerUid)",
                        chain: chain,
                        contractAddress: firstAsset.nftUid.contractAddress,
                        name: collectionMetadata?.name ?? providerUid,
                        imageUrl: collectionMetadata?.thumbnailImageUrl ?? firstAsset.previewImageUrl,
                        market: market,
                        marketUrl: marketProvider.collectionUrl(chain: chain, providerUid: providerUid),
                        items: mappedAssets
                    )
                }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

                return NftV2InventoryPayload(collections: collections)
            }
    }
}

final class NftV2WalletInventoryProvider: INftV2InventoryProvider {
    private struct ContextState {
        var metadataByUid = [NftUid: NftV2OnChainAssetMetadata]()
        var pancakeV3Records = [NftRecord]()
        var lastUpdatedAt: TimeInterval = Date().timeIntervalSince1970
        var lastPancakeV3SyncAt: TimeInterval = 0
    }

    private static let pancakeV3PositionManagerAddress = "0x46A15B0b27311cedF172AB29E4f4766fbE7F4364"
    private static let maxCachedContexts = 12
    private static let pancakeV3SyncThrottleInterval: TimeInterval = 120

    let chain: NftV2Chain
    let availability: NftV2ProviderAvailability = .available
    var updatesObservable: Observable<NftV2ProviderUpdate> {
        updatesRelay.asObservable()
    }

    private let nftAdapterManager: NftAdapterManager
    private let nftMetadataManager: NftMetadataManager
    private let marketProvider: NftV2MarketProvider
    private let onChainMetadataProvider: NftV2OnChainMetadataProvider
    private let evmBlockchainManager: EvmBlockchainManager
    private let evmSyncSourceManager: EvmSyncSourceManager
    private let disposeBag = DisposeBag()
    private let updatesRelay = PublishRelay<NftV2ProviderUpdate>()
    private let stateQueue = DispatchQueue(label: "\(AppConfig.label).nft_v2_wallet_inventory_provider_state")
    private var contextStateByKey = [String: ContextState]()
    private var syncingOnChainMetadataContexts = Set<String>()

    init(
        chain: NftV2Chain,
        nftAdapterManager: NftAdapterManager,
        nftMetadataManager: NftMetadataManager,
        marketProvider: NftV2MarketProvider,
        onChainMetadataProvider: NftV2OnChainMetadataProvider,
        evmBlockchainManager: EvmBlockchainManager,
        evmSyncSourceManager: EvmSyncSourceManager
    ) {
        self.chain = chain
        self.nftAdapterManager = nftAdapterManager
        self.nftMetadataManager = nftMetadataManager
        self.marketProvider = marketProvider
        self.onChainMetadataProvider = onChainMetadataProvider
        self.evmBlockchainManager = evmBlockchainManager
        self.evmSyncSourceManager = evmSyncSourceManager
    }

    func load(address: String, account: Account) -> Single<NftV2InventoryPayload> {
        let nftKey = NftKey(account: account, blockchainType: chain.blockchainType)
        guard let adapter = nftAdapterManager.adapter(nftKey: nftKey) else {
            return .just(NftV2InventoryPayload(collections: []))
        }

        return immediatePayloadSingle(adapter: adapter, address: address, account: account)
            .flatMap { [weak self] immediatePayload -> Single<NftV2InventoryPayload> in
                guard let self else {
                    return .just(immediatePayload)
                }

                let metadata = self.cachedMetadata(account: account)
                let contextKey = self.metadataContextKey(address: address, account: account)
                let cachedOnChainMetadata = self.cachedOnChainMetadataMap(contextKey: contextKey)
                let immediateRecordsCount = immediatePayload.collections.reduce(0) { $0 + $1.items.count }

                if immediateRecordsCount > 0 {
                    let immediateRecords = adapter.nftRecords.filter { $0.balance > 0 }
                    self.scheduleOnChainMetadataRefreshIfNeeded(
                        records: immediateRecords,
                        metadata: metadata,
                        address: address,
                        account: account,
                        contextKey: contextKey
                    )

                    let refreshedPayload = self.payload(
                        records: immediateRecords,
                        metadata: metadata,
                        onChainMetadataMap: cachedOnChainMetadata,
                        account: account
                    )

                    return .just(refreshedPayload)
                }

                return self.recordsSingle(adapter: adapter, account: account)
                    .flatMap { records -> Single<NftV2InventoryPayload> in
                        guard !records.isEmpty else {
                            return .just(immediatePayload)
                        }

                        self.scheduleOnChainMetadataRefreshIfNeeded(
                            records: records,
                            metadata: metadata,
                            address: address,
                            account: account,
                            contextKey: contextKey
                        )

                        let fastPayload = self.payload(
                            records: records,
                            metadata: metadata,
                            onChainMetadataMap: cachedOnChainMetadata,
                            account: account
                        )
                        return .just(fastPayload)
                    }
                    .catchErrorJustReturn(immediatePayload)
            }
    }

    func canLoad(address _: String, account: Account) -> Bool {
        let nftKey = NftKey(account: account, blockchainType: chain.blockchainType)
        return nftAdapterManager.adapter(nftKey: nftKey) != nil
    }

    func localPayload(address _: String, account: Account) -> NftV2InventoryPayload? {
        let nftKey = NftKey(account: account, blockchainType: chain.blockchainType)
        guard let adapter = nftAdapterManager.adapter(nftKey: nftKey) else {
            return nil
        }

        let records = adapter.nftRecords.filter { $0.balance > 0 }
        let metadata = cachedMetadata(account: account)
        let onChainMetadataMap = cachedOnChainMetadataMap(
            contextKey: metadataContextKey(address: adapter.userAddress, account: account)
        )
        return payload(records: records, metadata: metadata, onChainMetadataMap: onChainMetadataMap, account: account)
    }

    private func immediatePayloadSingle(adapter: INftAdapter, address: String, account: Account) -> Single<NftV2InventoryPayload> {
        let initialRecords = adapter.nftRecords.filter { $0.balance > 0 }
        guard !initialRecords.isEmpty else {
            adapter.sync()
            return .just(NftV2InventoryPayload(collections: []))
        }

        let metadata = cachedMetadata(account: account)
        let onChainMetadataMap = cachedOnChainMetadataMap(
            contextKey: metadataContextKey(address: address, account: account)
        )
        let payload = payload(
            records: initialRecords,
            metadata: metadata,
            onChainMetadataMap: onChainMetadataMap,
            account: account
        )
        return .just(payload)
    }

    private func recordsSingle(adapter: INftAdapter, account: Account) -> Single<[NftRecord]> {
        let initialRecords = adapter.nftRecords.filter { $0.balance > 0 }
        let initialCombinedRecordsSingle = mergePancakeV3RecordsSingle(baseRecords: initialRecords, account: account)
        adapter.sync()

        if !initialRecords.isEmpty {
            return initialCombinedRecordsSingle
        }

        let adapterRecordsSingle = adapter.nftRecordsObservable
            .map { records in
                records.filter { $0.balance > 0 }
            }
            .filter { !$0.isEmpty }
            .take(1)
            .timeout(.seconds(3), scheduler: ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .asSingle()
            .catchErrorJustReturn(initialRecords)

        return Single.zip(initialCombinedRecordsSingle, adapterRecordsSingle)
            .flatMap { _, adapterRecords in
                self.mergePancakeV3RecordsSingle(baseRecords: adapterRecords, account: account)
            }
    }

    private func mergePancakeV3Records(baseRecords: [NftRecord], supplemented: [NftRecord]) -> [NftRecord] {
        guard !supplemented.isEmpty else {
            return baseRecords
        }

        var merged = Dictionary(uniqueKeysWithValues: baseRecords.map { ($0.nftUid, $0) })
        for record in supplemented where merged[record.nftUid] == nil {
            merged[record.nftUid] = record
        }
        return Array(merged.values)
    }

    private func mergePancakeV3RecordsSingle(baseRecords: [NftRecord], account: Account) -> Single<[NftRecord]> {
        guard chain == .binanceSmartChain else {
            return .just(baseRecords)
        }

        let contextKey = metadataContextKey(address: normalizedAddress(account: account), account: account)
        let now = Date().timeIntervalSince1970
        if let cached = stateQueue.sync(execute: { contextStateByKey[contextKey] }),
           now - cached.lastPancakeV3SyncAt < Self.pancakeV3SyncThrottleInterval
        {
            return .just(mergePancakeV3Records(baseRecords: baseRecords, supplemented: cached.pancakeV3Records))
        }

        return pancakeV3LiquidityRecordsSingle(account: account)
            .map { supplemented in
                self.stateQueue.async {
                    var contextState = self.contextStateByKey[contextKey] ?? ContextState()
                    contextState.pancakeV3Records = supplemented
                    contextState.lastPancakeV3SyncAt = now
                    contextState.lastUpdatedAt = now
                    self.contextStateByKey[contextKey] = contextState
                    self.trimContextStatesIfNeeded()
                }

                return self.mergePancakeV3Records(baseRecords: baseRecords, supplemented: supplemented)
            }
            .catchErrorJustReturn(baseRecords)
    }

    private func normalizedAddress(account: Account) -> String {
        let nftKey = NftKey(account: account, blockchainType: chain.blockchainType)
        return nftAdapterManager.adapter(nftKey: nftKey)?.userAddress.lowercased() ?? ""
    }

    private func recordsRequiringOnChainMetadata(
        records: [NftRecord],
        metadata: (assetMap: [NftUid: NftAssetShortMetadata], collectionMap: [String: NftCollectionShortMetadata])?,
        cachedOnChainMetadataMap: [NftUid: NftV2OnChainAssetMetadata]
    ) -> [NftRecord] {
        records.filter { record in
            if let cachedOnChainMetadata = cachedOnChainMetadataMap[record.nftUid],
               cachedOnChainMetadata.name != nil,
               cachedOnChainMetadata.imageUrl != nil {
                return false
            }

            guard let assetMetadata = metadata?.assetMap[record.nftUid] else {
                return true
            }

            let hasName = !(assetMetadata.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            let hasPreviewImage = !(assetMetadata.previewImageUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

            return !hasName || !hasPreviewImage
        }
    }

    private func cachedMetadata(account: Account) -> (assetMap: [NftUid: NftAssetShortMetadata], collectionMap: [String: NftCollectionShortMetadata])? {
        let nftKey = NftKey(account: account, blockchainType: chain.blockchainType)
        return nftMetadataManager.addressMetadata(nftKey: nftKey).map(Self.metadataMaps)
    }

    private func cachedOnChainMetadataMap(contextKey: String) -> [NftUid: NftV2OnChainAssetMetadata] {
        return stateQueue.sync {
            contextStateByKey[contextKey]?.metadataByUid ?? [:]
        }
    }

    private func metadataContextKey(address: String, account: Account) -> String {
        let normalizedAddress = address.lowercased()
        return "\(account.id)|\(normalizedAddress)"
    }

    private func scheduleOnChainMetadataRefreshIfNeeded(
        records: [NftRecord],
        metadata: (assetMap: [NftUid: NftAssetShortMetadata], collectionMap: [String: NftCollectionShortMetadata])?,
        address: String,
        account: Account,
        contextKey: String
    ) {
        let cachedOnChainMetadata = cachedOnChainMetadataMap(contextKey: contextKey)
        let recordsForOnChain = recordsRequiringOnChainMetadata(
            records: records,
            metadata: metadata,
            cachedOnChainMetadataMap: cachedOnChainMetadata
        )

        guard !recordsForOnChain.isEmpty else {
            return
        }

        let shouldStartSync = stateQueue.sync { () -> Bool in
            if syncingOnChainMetadataContexts.contains(contextKey) {
                return false
            }

            syncingOnChainMetadataContexts.insert(contextKey)
            return true
        }

        guard shouldStartSync else {
            return
        }

        onChainMetadataProvider
            .assetMetadataSingle(records: recordsForOnChain, account: account, blockchainType: chain.blockchainType)
            .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .subscribe(onSuccess: { [weak self] metadataMap in
                guard let self else {
                    return
                }

                self.handleOnChainMetadataLoaded(
                    metadataMap,
                    chain: self.chain,
                    account: account,
                    address: address,
                    contextKey: contextKey
                )
            }, onError: { [weak self] _ in
                self?.finishOnChainMetadataSync(contextKey: contextKey)
            })
            .disposed(by: disposeBag)
    }

    private func handleOnChainMetadataLoaded(
        _ metadataMap: [NftUid: NftV2OnChainAssetMetadata],
        chain: NftV2Chain,
        account: Account,
        address: String,
        contextKey: String
    ) {
        let didChange = stateQueue.sync { () -> Bool in
            var contextState = contextStateByKey[contextKey] ?? ContextState()
            var changed = false

            for (nftUid, metadata) in metadataMap {
                if contextState.metadataByUid[nftUid] != metadata {
                    contextState.metadataByUid[nftUid] = metadata
                    changed = true
                }
            }

            contextState.lastUpdatedAt = Date().timeIntervalSince1970
            contextStateByKey[contextKey] = contextState
            syncingOnChainMetadataContexts.remove(contextKey)
            trimContextStatesIfNeeded()
            return changed
        }

        if didChange {
            updatesRelay.accept(
                NftV2ProviderUpdate(
                    chain: chain,
                    accountId: account.id,
                    address: address.lowercased()
                )
            )
        }
    }

    private func finishOnChainMetadataSync(contextKey: String) {
        stateQueue.async {
            self.syncingOnChainMetadataContexts.remove(contextKey)
        }
    }

    private func trimContextStatesIfNeeded() {
        guard contextStateByKey.count > Self.maxCachedContexts else {
            return
        }

        let removableKeys = contextStateByKey
            .sorted { $0.value.lastUpdatedAt < $1.value.lastUpdatedAt }
            .map(\.key)

        let removeCount = contextStateByKey.count - Self.maxCachedContexts
        for key in removableKeys.prefix(removeCount) {
            guard !syncingOnChainMetadataContexts.contains(key) else {
                continue
            }

            contextStateByKey.removeValue(forKey: key)
        }
    }

    private func pancakeV3LiquidityRecordsSingle(account: Account) -> Single<[NftRecord]> {
        guard let evmKitWrapper = try? evmBlockchainManager
            .evmKitManager(blockchainType: chain.blockchainType)
            .evmKitWrapper(account: account, blockchainType: chain.blockchainType)
        else {
            return .just([])
        }

        guard let kit = try? KitV3.instance(dexType: .pancakeSwap) else {
            return .just([])
        }
        guard let rpcSource = evmSyncSourceManager.httpSyncSource(blockchainType: chain.blockchainType)?.rpcSource else {
            return .just([])
        }

        return Single.create { observer in
            let task = Task(priority: .userInitiated) {
                do {
                    let positions = try await kit.ownedLiquidity(
                        rpcSource: rpcSource,
                        chain: .binanceSmartChain,
                        owner: evmKitWrapper.evmKit.address
                    )

                    let records = positions.map { position in
                        EvmNftRecord(
                            blockchainType: self.chain.blockchainType,
                            type: .eip721,
                            contractAddress: Self.pancakeV3PositionManagerAddress,
                            tokenId: position.tokenId.description,
                            tokenName: "Pancake V3 Position",
                            balance: 1
                        )
                    }

                    observer(.success(records))
                } catch {
                    observer(.success([]))
                }
            }

            return Disposables.create {
                task.cancel()
            }
        }
    }

    private static func metadataMaps(from metadata: NftAddressMetadata) -> (assetMap: [NftUid: NftAssetShortMetadata], collectionMap: [String: NftCollectionShortMetadata]) {
        let assetMap = Dictionary(uniqueKeysWithValues: metadata.assets.map { ($0.nftUid, $0) })
        let collectionMap = Dictionary(uniqueKeysWithValues: metadata.collections.map { ($0.providerUid, $0) })
        return (assetMap, collectionMap)
    }

    private func payload(
        records: [NftRecord],
        metadata: (assetMap: [NftUid: NftAssetShortMetadata], collectionMap: [String: NftCollectionShortMetadata])?,
        onChainMetadataMap: [NftUid: NftV2OnChainAssetMetadata],
        account: Account
    ) -> NftV2InventoryPayload {
        guard !records.isEmpty else {
            return NftV2InventoryPayload(collections: [])
        }

        let items = records.map { record in
            NftV2WalletInventoryItem(
                record: record,
                assetMetadata: metadata?.assetMap[record.nftUid],
                onChainMetadata: onChainMetadataMap[record.nftUid]
            )
        }

        let collectionMap = metadata?.collectionMap ?? [:]
        let market = marketProvider.primaryMarket(chain: chain)
        let groupedItems = Dictionary(grouping: items) { item -> String in
            item.assetMetadata?.providerCollectionUid ?? item.record.nftUid.contractAddress.lowercased()
        }

        let collections = groupedItems.compactMap { collectionId, items in
            buildCollection(
                collectionId: collectionId,
                items: items,
                collectionMap: collectionMap,
                market: market,
                account: account
            )
        }
        .sorted(by: Self.collectionSort)

        return NftV2InventoryPayload(collections: collections)
    }

    private func buildCollection(
        collectionId: String,
        items: [NftV2WalletInventoryItem],
        collectionMap: [String: NftCollectionShortMetadata],
        market: NftV2Market?,
        account: Account
    ) -> NftV2Collection? {
        guard let firstItem = items.first else {
            return nil
        }

        let firstRecord = firstItem.record
        let contractAddress = firstRecord.nftUid.contractAddress
        let collectionMetadata = collectionMap[collectionId]
        let assets = buildAssets(
            items: items,
            contractAddress: contractAddress,
            collectionMetadata: collectionMetadata,
            firstRecord: firstRecord,
            market: market,
            account: account
        )

        let collectionEntryId = "\(chain.rawValue)-\(collectionId)"
        let collectionName = collectionMetadata?.name ?? firstItem.onChainMetadata?.collectionName ?? fallbackCollectionName(record: firstRecord)
        let collectionImageUrl = collectionMetadata?.thumbnailImageUrl ?? firstItem.onChainMetadata?.imageUrl ?? assets.first?.imageUrl
        let collectionMarketUrl = collectionMetadata.flatMap { metadata in
            marketProvider.collectionUrl(chain: chain, providerUid: metadata.providerUid)
        }

        return NftV2Collection(
            id: collectionEntryId,
            chain: chain,
            contractAddress: contractAddress,
            name: collectionName,
            imageUrl: collectionImageUrl,
            market: market,
            marketUrl: collectionMarketUrl,
            items: assets
        )
    }

    private func buildAssets(
        items: [NftV2WalletInventoryItem],
        contractAddress: String,
        collectionMetadata: NftCollectionShortMetadata?,
        firstRecord: NftRecord,
        market: NftV2Market?,
        account: Account
    ) -> [NftV2Asset] {
        items.map { item in
            buildAsset(
                item: item,
                contractAddress: contractAddress,
                collectionMetadata: collectionMetadata,
                firstRecord: firstRecord,
                market: market,
                account: account
            )
        }
        .sorted(by: Self.assetSort)
    }

    private func buildAsset(
        item: NftV2WalletInventoryItem,
        contractAddress: String,
        collectionMetadata: NftCollectionShortMetadata?,
        firstRecord: NftRecord,
        market: NftV2Market?,
        account: Account
    ) -> NftV2Asset {
        let metadata = item.assetMetadata
        let nftUid = item.record.nftUid
        let assetId = nftUid.uid
        let tokenId = nftUid.tokenId
        let standard = "nft_v2.asset.standard".localized
        let imageUrl = metadata?.previewImageUrl ?? item.onChainMetadata?.imageUrl
        let balance = item.record.balance
        let assetName = metadata?.displayName ?? item.onChainMetadata?.name ?? fallbackAssetName(record: item.record)
        let collectionName = collectionMetadata?.name ?? item.onChainMetadata?.collectionName ?? fallbackCollectionName(record: firstRecord)
        let transferType = transferType(record: item.record)
        let assetMarketUrl = marketProvider.assetUrl(
            chain: chain,
            contractAddress: contractAddress,
            tokenId: tokenId
        )
        let canSend = !account.watchAccount

        return NftV2Asset(
            id: assetId,
            nftUid: nftUid,
            chain: chain,
            contractAddress: contractAddress,
            tokenId: tokenId,
            standard: standard,
            name: assetName,
            imageUrl: imageUrl,
            collectionName: collectionName,
            market: market,
            marketUrl: assetMarketUrl,
            balance: balance,
            canSend: canSend,
            transferType: transferType
        )
    }

    private static func assetSort(lhs: NftV2Asset, rhs: NftV2Asset) -> Bool {
        lhs.tokenId.localizedStandardCompare(rhs.tokenId) == .orderedAscending
    }

    private static func collectionSort(lhs: NftV2Collection, rhs: NftV2Collection) -> Bool {
        lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private func fallbackAssetName(record: NftRecord) -> String {
        if let evmRecord = record as? EvmNftRecord, let tokenName = evmRecord.tokenName, !tokenName.isEmpty {
            return "\(tokenName) #\(record.nftUid.tokenId)"
        }

        return "#\(record.nftUid.tokenId)"
    }

    private func fallbackCollectionName(record: NftRecord) -> String {
        if let evmRecord = record as? EvmNftRecord, let tokenName = evmRecord.tokenName, !tokenName.isEmpty {
            return tokenName
        }

        return record.nftUid.contractAddress.shortened
    }

    private func transferType(record: NftRecord) -> NftV2TransferType {
        guard let evmRecord = record as? EvmNftRecord else {
            return .unknown
        }

        switch evmRecord.type {
        case .eip721: return .eip721
        case .eip1155: return .eip1155
        }
    }
}
