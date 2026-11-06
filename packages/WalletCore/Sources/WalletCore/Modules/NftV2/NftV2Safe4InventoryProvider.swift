import BigInt
import Foundation
import MarketKit
import RxRelay
import RxSwift
import Web3Core

protocol INftV2Safe4InventoryProvider: INftV2InventoryProvider {
    func load(address: String, account: Account, safe4ChainId: Int) -> Single<NftV2InventoryPayload>
    func loadCollectionItems(address: String, account: Account, contractAddress: String, safe4ChainId: Int) -> Single<Void>
}

final class NftV2Safe4InventoryProvider: INftV2Safe4InventoryProvider {
    private static let maxCachedInventories = 12

    private struct CachedInventory {
        let address: String
        let account: Account
        let holdings: [SRC721InsightHolding]
        var assetsByContract: [String: [SRC721InsightAsset]]
        var loadedAssetContractKeys: Set<String>
        var updatedAt: TimeInterval
    }

    let chain: NftV2Chain = .safe4
    let availability: NftV2ProviderAvailability = .available

    private let nftMetadataManager: NftMetadataManager
    private let marketProvider: NftV2MarketProvider
    private let insightProviderFactory: (Int) -> SRC721InsightAssetProvider
    private let stateQueue = DispatchQueue(label: "\(AppConfig.label).nft_v2_safe4_inventory_provider")
    private let updatesRelay = PublishRelay<NftV2ProviderUpdate>()
    private var cachedCatalogByChainId = [Int: [SRC721InsightToken]]()
    private var completedCatalogRequestsByChainId = Set<Int>()
    private var cachedInventoryByContext = [String: CachedInventory]()
    private var catalogRequestsInFlight = Set<Int>()

    var updatesObservable: Observable<NftV2ProviderUpdate> {
        updatesRelay.asObservable()
    }

    init(
        nftMetadataManager: NftMetadataManager,
        marketProvider: NftV2MarketProvider,
        insightProviderFactory: @escaping (Int) -> SRC721InsightAssetProvider = { SRC721InsightProvider(chainId: $0) }
    ) {
        self.nftMetadataManager = nftMetadataManager
        self.marketProvider = marketProvider
        self.insightProviderFactory = insightProviderFactory
    }

    func load(address: String, account: Account) -> Single<NftV2InventoryPayload> {
        load(address: address, account: account, safe4ChainId: Safe4Network.currentChainId)
    }

    func load(address: String, account: Account, safe4ChainId chainId: Int) -> Single<NftV2InventoryPayload> {
        let insight = insightProviderFactory(chainId)

        return Single.create { [weak self] observer in
            let task = Task {
                do {
                    let holdings = try await insight.holdings(owner: address)
                    if !holdings.isEmpty {
                        // Fetch names while per-contract assets are loading, rather than
                        // waiting for the complete inventory before starting the catalog.
                        // Catalog failure is independent and a later load can retry it.
                        self?.fetchCatalogIfNeeded(chainId: chainId, address: address, account: account, insight: insight)
                    }

                    guard let self else {
                        observer(.success(NftV2InventoryPayload(collections: [])))
                        return
                    }

                    let cacheKey = self.inventoryCacheKey(chainId: chainId, address: address, account: account)
                    let contractRequests = Self.contractRequests(holdings: holdings, owner: address)
                    let assetsByContract = Dictionary(uniqueKeysWithValues: contractRequests.map { ($0.key, [SRC721InsightAsset]()) })

                    guard Safe4Network.isCurrent(chainId: chainId) else {
                        throw Safe4NetworkError.staleContext(expected: chainId, current: Safe4Network.currentChainId)
                    }

                    self.stateQueue.sync {
                        self.cachedInventoryByContext[cacheKey] = CachedInventory(
                            address: address,
                            account: account,
                            holdings: holdings,
                            assetsByContract: assetsByContract,
                            loadedAssetContractKeys: [],
                            updatedAt: Date().timeIntervalSince1970
                        )
                        while self.cachedInventoryByContext.count > Self.maxCachedInventories,
                              let oldest = self.cachedInventoryByContext.min(by: { $0.value.updatedAt < $1.value.updatedAt })?.key {
                            self.cachedInventoryByContext.removeValue(forKey: oldest)
                        }
                    }

                    let (catalog, catalogResolved) = self.stateQueue.sync {
                        (self.cachedCatalogByChainId[chainId] ?? [], self.completedCatalogRequestsByChainId.contains(chainId))
                    }
                    let payload = self.payload(
                        address: address,
                        account: account,
                        holdings: holdings,
                        catalog: catalog,
                        assetsByContract: assetsByContract,
                        catalogResolved: catalogResolved
                    )
                    observer(.success(payload))
                } catch {
                    observer(.error(error))
                }
            }

            return Disposables.create { task.cancel() }
        }
    }

    func loadCollectionItems(address: String, account: Account, contractAddress: String, safe4ChainId chainId: Int) -> Single<Void> {
        let insight = insightProviderFactory(chainId)
        guard let normalizedContract = Self.normalizedAddress(contractAddress) else {
            return .error(SRC721InsightError.invalidResponse)
        }
        let cacheKey = inventoryCacheKey(chainId: chainId, address: address, account: account)
        let contractKey = normalizedContract.lowercased()

        return Single.create { [weak self] observer in
            let task = Task {
                do {
                    guard let self,
                          let cached = self.stateQueue.sync(execute: { self.cachedInventoryByContext[cacheKey] }) else {
                        throw SRC721InsightError.invalidResponse
                    }
                    if cached.loadedAssetContractKeys.contains(contractKey) {
                        observer(.success(()))
                        return
                    }
                    let assets = try await insight.assets(owner: address, tokenAddress: normalizedContract)
                    guard Safe4Network.isCurrent(chainId: chainId) else {
                        throw Safe4NetworkError.staleContext(expected: chainId, current: Safe4Network.currentChainId)
                    }
                    let loaded = self.stateQueue.sync { () -> Bool in
                        guard var current = self.cachedInventoryByContext[cacheKey] else { return false }
                        current.assetsByContract[contractKey] = assets
                        current.loadedAssetContractKeys.insert(contractKey)
                        current.updatedAt = Date().timeIntervalSince1970
                        self.cachedInventoryByContext[cacheKey] = current
                        return true
                    }
                    guard loaded else { throw SRC721InsightError.invalidResponse }
                    observer(.success(()))
                    self.updatesRelay.accept(NftV2ProviderUpdate(
                        chain: .safe4,
                        accountId: ChildWalletBridge.shared.contextAccountId(account: account),
                        address: address.lowercased()
                    ))
                } catch {
                    observer(.error(error))
                }
            }
            return Disposables.create { task.cancel() }
        }
    }

    func canLoad(address _: String, account _: Account) -> Bool {
        true
    }

    func localPayload(address: String, account: Account) -> NftV2InventoryPayload? {
        let chainId = Safe4Network.currentChainId
        let cacheKey = inventoryCacheKey(chainId: chainId, address: address, account: account)
        guard let cached = stateQueue.sync(execute: { cachedInventoryByContext[cacheKey] }) else {
            return nil
        }
        let (catalog, catalogResolved) = stateQueue.sync {
            (cachedCatalogByChainId[chainId] ?? [], completedCatalogRequestsByChainId.contains(chainId))
        }
        return payload(
            address: cached.address,
            account: cached.account,
            holdings: cached.holdings,
            catalog: catalog,
            assetsByContract: cached.assetsByContract,
            catalogResolved: catalogResolved
        )
    }

    private func fetchCatalogIfNeeded(
        chainId: Int,
        address: String,
        account: Account,
        insight: SRC721InsightAssetProvider
    ) {
        let shouldStart = stateQueue.sync { () -> Bool in
            guard cachedCatalogByChainId[chainId] == nil,
                  catalogRequestsInFlight.insert(chainId).inserted else {
                return false
            }
            completedCatalogRequestsByChainId.remove(chainId)
            return true
        }
        guard shouldStart else { return }

        let accountId = ChildWalletBridge.shared.contextAccountId(account: account)
        Task { [weak self] in
            let catalog = try? await insight.tokens()
            guard let self else { return }

            let shouldPublish = self.stateQueue.sync { () -> Bool in
                self.catalogRequestsInFlight.remove(chainId)
                guard Safe4Network.isCurrent(chainId: chainId) else {
                    return false
                }
                if let catalog {
                    self.cachedCatalogByChainId[chainId] = catalog
                }
                self.completedCatalogRequestsByChainId.insert(chainId)
                return true
            }

            if shouldPublish {
                self.updatesRelay.accept(
                    NftV2ProviderUpdate(
                        chain: .safe4,
                        accountId: accountId,
                        address: address.lowercased()
                    )
                )
            }
        }
    }

    private func inventoryCacheKey(chainId: Int, address: String, account: Account) -> String {
        "\(chainId)|\(ChildWalletBridge.shared.contextAccountId(account: account))|\(address.lowercased())"
    }

    private func payload(
        address: String,
        account: Account,
        holdings: [SRC721InsightHolding],
        catalog: [SRC721InsightToken],
        assetsByContract: [String: [SRC721InsightAsset]],
        catalogResolved: Bool
    ) -> NftV2InventoryPayload {
        let nftKey = NftKey(account: account, blockchainType: chain.blockchainType)
        let cachedMetadata = nftMetadataManager.addressMetadata(nftKey: nftKey)
        let assetMetadataByUid = Dictionary(
            (cachedMetadata?.assets ?? []).map { ($0.nftUid, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let collectionMetadataById = Dictionary(
            (cachedMetadata?.collections ?? []).map { ($0.providerUid, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let tokensByAddress = Dictionary(
            catalog.compactMap { token -> (String, SRC721InsightToken)? in
                guard token.isERC721,
                      let normalized = Self.normalizedAddress(token.address)
                else { return nil }
                return (normalized.lowercased(), token)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let normalizedOwner = Self.normalizedAddress(address)?.lowercased() ?? address.lowercased()
        var emittedContractAddresses = Set<String>()
        let market = marketProvider.primaryMarket(chain: chain)
        let collections = holdings.compactMap { holding -> NftV2Collection? in
            guard holding.owner.lowercased() == normalizedOwner,
                  let contractAddress = Self.normalizedAddress(holding.token),
                  let assets = assetsByContract[contractAddress.lowercased()],
                  emittedContractAddresses.insert(contractAddress.lowercased()).inserted
            else { return nil }
            let reportedItemCount = Int(holding.count) ?? 0
            guard reportedItemCount > 0 || !assets.isEmpty else { return nil }

            let token = tokensByAddress[contractAddress.lowercased()]
            let contractAssets = assets.compactMap { insightAsset -> NftV2Asset? in
                guard let tokenId = Self.ownedTokenId(
                    for: insightAsset,
                    owner: normalizedOwner,
                    contractAddress: contractAddress
                )
                else { return nil }

                let nftUid = NftUid.evm(
                    blockchainType: chain.blockchainType,
                    contractAddress: contractAddress,
                    tokenId: tokenId
                )
                let metadata = assetMetadataByUid[nftUid]
                let collectionMetadata = metadata.flatMap { collectionMetadataById[$0.providerCollectionUid] }
                return NftV2Asset(
                    id: nftUid.uid,
                    nftUid: nftUid,
                    chain: chain,
                    contractAddress: contractAddress,
                    tokenId: tokenId,
                    standard: "nft_v2.asset.standard".localized,
                    name: metadata?.displayName ?? "#\(tokenId)",
                    imageUrl: Self.resourceUrl(insightAsset.tokenImage) ?? metadata?.previewImageUrl,
                    collectionName: collectionMetadata?.name ?? token?.name ?? contractAddress.shortened,
                    market: market,
                    marketUrl: marketProvider.assetUrl(chain: chain, contractAddress: contractAddress, tokenId: tokenId),
                    balance: 1,
                    canSend: !account.watchAccount,
                    transferType: .eip721
                )
            }

            let uniqueAssets = Dictionary(
                contractAssets.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            ).values.sorted { $0.tokenId.localizedStandardCompare($1.tokenId) == .orderedAscending }

            let collectionMetadata = uniqueAssets.first.flatMap { assetMetadataByUid[$0.nftUid] }
                .flatMap { collectionMetadataById[$0.providerCollectionUid] }
            let metadataName = collectionMetadata?.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let tokenName = token?.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedName = metadataName.flatMap { $0.isEmpty ? nil : $0 }
                ?? tokenName.flatMap { $0.isEmpty ? nil : $0 }
            let name = resolvedName ?? contractAddress.shortened
            return NftV2Collection(
                id: "\(chain.rawValue)-\(contractAddress.lowercased())",
                chain: chain,
                contractAddress: contractAddress,
                name: name,
                imageUrl: collectionMetadata?.thumbnailImageUrl ?? Self.resourceUrl(token?.logoURI) ?? uniqueAssets.first?.imageUrl,
                market: market,
                marketUrl: nil,
                items: uniqueAssets,
                reportedItemCount: reportedItemCount,
                isNameResolved: resolvedName != nil || catalogResolved
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return NftV2InventoryPayload(collections: collections)
    }

    static func contractRequests(holdings: [SRC721InsightHolding], owner: String) -> [(key: String, address: String)] {
        var seen = Set<String>()
        return holdings.compactMap { holding in
            guard holding.owner.caseInsensitiveCompare(owner) == .orderedSame,
                  let address = normalizedAddress(holding.token)
            else { return nil }
            let key = address.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return (key, address)
        }
    }

    static func ownedTokenId(
        for asset: SRC721InsightAsset,
        owner: String,
        contractAddress: String
    ) -> String? {
        guard asset.isERC721,
              let assetOwner = normalizedAddress(asset.owner),
              let normalizedOwner = normalizedAddress(owner),
              assetOwner.caseInsensitiveCompare(normalizedOwner) == .orderedSame,
              let assetContract = normalizedAddress(asset.token),
              let normalizedContract = normalizedAddress(contractAddress),
              assetContract.caseInsensitiveCompare(normalizedContract) == .orderedSame,
              let tokenId = BigUInt(asset.tokenId)
        else { return nil }

        // SafeZone treats the indexer's ERC-721 asset list as authoritative and does not
        // exclude entries based on tokenValue. Keep the portfolio view consistent with it.
        return tokenId.description
    }

    private static func normalizedAddress(_ value: String) -> String? {
        Web3Core.EthereumAddress(value)?.address
    }

    private static func resourceUrl(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("ipfs://ipfs/") {
            return "https://ipfs.io/ipfs/\(trimmed.dropFirst("ipfs://ipfs/".count))"
        }
        if trimmed.hasPrefix("ipfs://") {
            return "https://ipfs.io/ipfs/\(trimmed.dropFirst("ipfs://".count))"
        }
        guard !trimmed.lowercased().hasPrefix("data:") else { return nil }
        return trimmed.isEmpty ? nil : trimmed
    }
}
