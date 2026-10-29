import BigInt
import Foundation
import MarketKit
import RxRelay
import RxSwift
import Web3Core

final class NftV2Safe4InventoryProvider: INftV2InventoryProvider {
    static let maxConcurrentContractRequests = 4
    private static let maxCachedInventories = 12

    private struct CachedInventory {
        let address: String
        let account: Account
        let holdings: [SRC721InsightHolding]
        let assetsByContract: [String: [SRC721InsightAsset]]
        let updatedAt: TimeInterval
    }

    struct AssetFetchResult {
        let assetsByContract: [String: [SRC721InsightAsset]]
        let failedContractKeys: Set<String>
    }

    let chain: NftV2Chain = .safe4
    let availability: NftV2ProviderAvailability = .available

    private let nftMetadataManager: NftMetadataManager
    private let marketProvider: NftV2MarketProvider
    private let insightProviderFactory: (Int) -> SRC721InsightAssetProvider
    private let stateQueue = DispatchQueue(label: "\(AppConfig.label).nft_v2_safe4_inventory_provider")
    private let updatesRelay = PublishRelay<NftV2ProviderUpdate>()
    private var cachedCatalogByChainId = [Int: [SRC721InsightToken]]()
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
        let chainId = Safe4Network.currentChainId
        let insight = insightProviderFactory(chainId)

        return Single.create { [weak self] observer in
            let task = Task {
                do {
                    let holdings = try await insight.holdings(owner: address)
                    let contractRequests = Self.contractRequests(holdings: holdings, owner: address)
                    let fetchedAssets = await Self.fetchAssets(
                        requests: contractRequests,
                        owner: address,
                        insight: insight
                    )

                    guard let self else {
                        observer(.success(NftV2InventoryPayload(collections: [])))
                        return
                    }

                    let cacheKey = self.inventoryCacheKey(chainId: chainId, address: address, account: account)
                    let previousAssets = self.stateQueue.sync {
                        self.cachedInventoryByContext[cacheKey]?.assetsByContract ?? [:]
                    }
                    var assetsByContract = fetchedAssets.assetsByContract
                    for key in fetchedAssets.failedContractKeys {
                        if let previous = previousAssets[key] {
                            assetsByContract[key] = previous
                        }
                    }

                    if !contractRequests.isEmpty,
                       fetchedAssets.failedContractKeys.count == contractRequests.count {
                        throw SRC721InsightError.invalidResponse
                    }

                    guard Safe4Network.isCurrent(chainId: chainId) else {
                        throw Safe4NetworkError.staleContext(expected: chainId, current: Safe4Network.currentChainId)
                    }

                    self.stateQueue.sync {
                        self.cachedInventoryByContext[cacheKey] = CachedInventory(
                            address: address,
                            account: account,
                            holdings: holdings,
                            assetsByContract: assetsByContract,
                            updatedAt: Date().timeIntervalSince1970
                        )
                        while self.cachedInventoryByContext.count > Self.maxCachedInventories,
                              let oldest = self.cachedInventoryByContext.min(by: { $0.value.updatedAt < $1.value.updatedAt })?.key {
                            self.cachedInventoryByContext.removeValue(forKey: oldest)
                        }
                    }

                    let catalog = self.stateQueue.sync { self.cachedCatalogByChainId[chainId] }
                    let payload = self.payload(
                        address: address,
                        account: account,
                        holdings: holdings,
                        catalog: catalog ?? [],
                        assetsByContract: assetsByContract
                    )
                    observer(.success(payload))
                    if catalog == nil, !holdings.isEmpty {
                        self.fetchCatalogIfNeeded(chainId: chainId, address: address, account: account, insight: insight)
                    }
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
        let catalog = stateQueue.sync { cachedCatalogByChainId[chainId] ?? [] }
        return payload(
            address: cached.address,
            account: cached.account,
            holdings: cached.holdings,
            catalog: catalog,
            assetsByContract: cached.assetsByContract
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
            return true
        }
        guard shouldStart else { return }

        let accountId = ChildWalletBridge.shared.contextAccountId(account: account)
        Task { [weak self] in
            let catalog = try? await insight.tokens()
            guard let self else { return }

            let shouldPublish = self.stateQueue.sync { () -> Bool in
                self.catalogRequestsInFlight.remove(chainId)
                guard let catalog,
                      Safe4Network.isCurrent(chainId: chainId) else {
                    return false
                }
                self.cachedCatalogByChainId[chainId] = catalog
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
        assetsByContract: [String: [SRC721InsightAsset]]
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
                  let holdingCount = BigUInt(holding.count), holdingCount > 0,
                  let assets = assetsByContract[contractAddress.lowercased()],
                  emittedContractAddresses.insert(contractAddress.lowercased()).inserted
            else { return nil }

            let token = tokensByAddress[contractAddress.lowercased()]
            let contractAssets = assets.compactMap { insightAsset -> NftV2Asset? in
                guard let assetContract = Self.normalizedAddress(insightAsset.token) else { return nil }
                guard insightAsset.isERC721,
                      insightAsset.owner.lowercased() == normalizedOwner,
                      assetContract.caseInsensitiveCompare(contractAddress) == .orderedSame,
                      let tokenValue = BigUInt(insightAsset.tokenValue), tokenValue > 0,
                      BigUInt(insightAsset.tokenId) != nil
                else { return nil }

                let nftUid = NftUid.evm(
                    blockchainType: chain.blockchainType,
                    contractAddress: contractAddress,
                    tokenId: insightAsset.tokenId
                )
                let metadata = assetMetadataByUid[nftUid]
                let collectionMetadata = metadata.flatMap { collectionMetadataById[$0.providerCollectionUid] }
                let tokenId = insightAsset.tokenId

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
            guard !uniqueAssets.isEmpty else { return nil }

            let collectionMetadata = uniqueAssets.first.flatMap { assetMetadataByUid[$0.nftUid] }
                .flatMap { collectionMetadataById[$0.providerCollectionUid] }
            let name = collectionMetadata?.name ?? token?.name ?? contractAddress.shortened
            return NftV2Collection(
                id: "\(chain.rawValue)-\(contractAddress.lowercased())",
                chain: chain,
                contractAddress: contractAddress,
                name: name,
                imageUrl: collectionMetadata?.thumbnailImageUrl ?? Self.resourceUrl(token?.logoURI) ?? uniqueAssets.first?.imageUrl,
                market: market,
                marketUrl: nil,
                items: uniqueAssets
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return NftV2InventoryPayload(collections: collections)
    }

    static func contractRequests(holdings: [SRC721InsightHolding], owner: String) -> [(key: String, address: String)] {
        var seen = Set<String>()
        return holdings.compactMap { holding in
            guard holding.owner.caseInsensitiveCompare(owner) == .orderedSame,
                  let count = BigUInt(holding.count), count > 0,
                  let address = normalizedAddress(holding.token)
            else { return nil }
            let key = address.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return (key, address)
        }
    }

    static func fetchAssets(
        requests: [(key: String, address: String)],
        owner: String,
        insight: SRC721InsightAssetProvider
    ) async -> AssetFetchResult {
        await withTaskGroup(of: (String, [SRC721InsightAsset]?).self) { group in
            var nextIndex = 0
            for _ in 0 ..< min(maxConcurrentContractRequests, requests.count) {
                let request = requests[nextIndex]
                group.addTask { (request.key, try? await insight.assets(owner: owner, tokenAddress: request.address)) }
                nextIndex += 1
            }

            var results = [String: [SRC721InsightAsset]]()
            var failedKeys = Set<String>()
            while let (key, assets) = await group.next() {
                if let assets {
                    results[key] = assets
                } else {
                    failedKeys.insert(key)
                }
                guard nextIndex < requests.count else { continue }
                let request = requests[nextIndex]
                group.addTask { (request.key, try? await insight.assets(owner: owner, tokenAddress: request.address)) }
                nextIndex += 1
            }
            return AssetFetchResult(assetsByContract: results, failedContractKeys: failedKeys)
        }
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
