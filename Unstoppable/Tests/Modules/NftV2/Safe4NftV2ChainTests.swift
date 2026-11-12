import Foundation
import Testing
import MarketKit
import NftKit
import EvmKit
import RxSwift
import XCTest
@testable import WalletCore

struct Safe4NftV2ChainTests {
    @Test func safe4ParticipatesInNftV2AsEip721Chain() {
        #expect(NftV2Chain.allCases.contains(.safe4))
        #expect(NftV2Chain.safe4.blockchainType == .safe4)
        #expect(BlockchainType.safe4.supportedNftTypes == [.eip721])
        #expect(NftV2MarketProvider().primaryMarket(chain: .safe4) == nil)
    }

    @Test func safe4CollectionCanShowReportedCountBeforeItemsAreLoaded() {
        let collection = NftV2Collection(
            id: "safe4-collection",
            chain: .safe4,
            contractAddress: "0x0000000000000000000000000000000000000001",
            name: "Collection",
            imageUrl: nil,
            market: nil,
            marketUrl: nil,
            items: [],
            reportedItemCount: 116
        )

        #expect(collection.count == 116)
    }

    @Test func safe4InsightDiscoveryDeduplicatesContractsIncludingZeroCountHoldings() throws {
        let owner = "0x4c207825db1c46dd836123e58ecae85de7025879"
        let holdingData = """
        [
          {"owner":"\(owner)","token":"0x0000000000000000000000000000000000000001","count":"2"},
          {"owner":"\(owner)","token":"0x0000000000000000000000000000000000000001","count":"1"},
          {"owner":"\(owner)","token":"0x0000000000000000000000000000000000000002","count":"0"},
          {"owner":"0x0000000000000000000000000000000000000003","token":"0x0000000000000000000000000000000000000004","count":"1"}
        ]
        """.data(using: .utf8)!
        let holdings = try JSONDecoder().decode([SRC721InsightHolding].self, from: holdingData)

        let requests = NftV2Safe4InventoryProvider.contractRequests(holdings: holdings, owner: owner)

        #expect(requests.count == 2)
        #expect(requests.first?.key == "0x0000000000000000000000000000000000000001")
        #expect(requests.last?.key == "0x0000000000000000000000000000000000000002")
    }

    @Test func safe4AssetValidationMatchesSafeZoneAndNormalizesTokenIds() throws {
        let owner = "0x4c207825db1c46dd836123e58ecae85de7025879"
        let contract = "0x0000000000000000000000000000000000000001"
        let data = """
        {"owner":"\(owner)","token":"\(contract)","tokenType":"erc721","tokenId":"0007","tokenValue":"0","tokenURI":null,"tokenImage":null}
        """.data(using: .utf8)!
        let asset = try JSONDecoder().decode(SRC721InsightAsset.self, from: data)

        #expect(NftV2Safe4InventoryProvider.ownedTokenId(for: asset, owner: owner, contractAddress: contract) == "7")
        #expect(NftV2Safe4InventoryProvider.ownedTokenId(for: asset, owner: contract, contractAddress: contract) == nil)
    }

    @Test func safe4SnapshotCacheKeepsMainnetAndTestnetInventoriesSeparate() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("safe4-nft-cache-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = NftV2SnapshotCacheStore(cacheDirectoryURL: directory)
        let accountId = UUID().uuidString
        let mainnetChainId = Safe4Network.chainId(testNet: false)
        let testnetChainId = Safe4Network.chainId(testNet: true)
        store.save(
            payload: snapshotPayload(collectionName: "Mainnet collection"),
            accountId: accountId,
            chain: .safe4,
            address: nil,
            market: nil,
            safe4ChainId: mainnetChainId
        )
        store.save(
            payload: snapshotPayload(collectionName: "Testnet collection"),
            accountId: accountId,
            chain: .safe4,
            address: nil,
            market: nil,
            safe4ChainId: testnetChainId
        )

        #expect(store.load(accountId: accountId, safe4ChainId: mainnetChainId)[.safe4]?.payload.collections.first?.name == "Mainnet collection")
        #expect(store.load(accountId: accountId, safe4ChainId: testnetChainId)[.safe4]?.payload.collections.first?.name == "Testnet collection")
    }

    @Test func safe4RefreshPreservesCachedNameButDoesNotReuseAddressPlaceholder() {
        let cached = snapshotPayload(collectionName: "My NFT").collections[0]
        var unresolved = snapshotPayload(collectionName: cached.contractAddress.shortened).collections[0]
        unresolved.isNameResolved = false
        let merged = NftV2InventoryService.mergedCollectionName(preferred: unresolved, fallback: cached)
        #expect(merged.name == "My NFT")
        #expect(merged.isResolved)

        // Older versions incorrectly persisted address placeholders as resolved.
        var legacy = unresolved
        legacy.isNameResolved = true
        #expect(!NftV2InventoryService.mergedCollectionName(preferred: unresolved, fallback: legacy).isResolved)
    }

    @Test func safe4SnapshotCacheRepairsLegacyAddressReadiness() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("safe4-nft-name-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NftV2SnapshotCacheStore(cacheDirectoryURL: directory)
        let payload = snapshotPayload(collectionName: "0x0000...0001")
        store.save(payload: payload, accountId: "test", chain: .safe4, address: nil, market: nil)
        let collection = try #require(store.load(accountId: "test")[.safe4]?.payload.collections.first)
        #expect(!collection.isNameResolved)
    }

    @Test func safe4SnapshotCacheIgnoresLegacyNetworklessSafe4EntryWithoutDroppingOtherChains() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("safe4-nft-legacy-cache-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let accountId = UUID().uuidString
        let legacyData = Data("""
        {"items":[
          {"chain":"safe4","address":null,"market":null,"hasDiscoveredInventory":true,"collections":[],"updatedAt":1},
          {"chain":"ethereum","address":null,"market":null,"hasDiscoveredInventory":true,"collections":[],"updatedAt":1}
        ]}
        """.utf8)
        try legacyData.write(to: directory.appendingPathComponent("snapshot_\(accountId).json"))

        let cached = NftV2SnapshotCacheStore(cacheDirectoryURL: directory)
            .load(accountId: accountId, safe4ChainId: Safe4Network.chainId(testNet: false))

        #expect(cached[.safe4] == nil)
        #expect(cached[.ethereum] != nil)
    }

    private func snapshotPayload(collectionName: String) -> NftV2InventoryPayload {
        NftV2InventoryPayload(collections: [
            NftV2Collection(
                id: collectionName,
                chain: .safe4,
                contractAddress: "0x0000000000000000000000000000000000000001",
                name: collectionName,
                imageUrl: nil,
                market: nil,
                marketUrl: nil,
                items: []
            )
        ])
    }
}

final class Safe4NftV2RefreshTests: XCTestCase {
    private let owner = "0x4c207825db1c46dd836123e58ecae85de7025879"
    private let contract = "0x0000000000000000000000000000000000000001"

    func testEmptyAndFailedCatalogAreRetriedWithoutLoadingItems() async throws {
        let suite = "safe4-nft-refresh-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let account = try makeAccount()
        let insight = ControlledNftInsight(owner: owner, contract: contract)
        let provider = NftV2Safe4InventoryProvider(
            addressMetadata: { _ in nil },
            marketProvider: NftV2MarketProvider(),
            contractStorage: SRC721Storage(defaults: defaults),
            insightProviderFactory: { _ in insight }
        )
        let bag = DisposeBag()

        // A successful empty directory must not become a permanent cache hit.
        let first = try await load(provider, account: account, bag: bag)
        XCTAssertEqual(first.collections.first?.isNameResolved, false)
        let emptyUpdate = expectation(description: "empty catalog applied")
        provider.updatesObservable.take(1).subscribe(onNext: { _ in emptyUpdate.fulfill() }).disposed(by: bag)
        await insight.finishCatalog(.success([]))
        await fulfillment(of: [emptyUpdate], timeout: 3)

        // A failed retry must leave the name unresolved, without failing holdings.
        let second = try await load(provider, account: account, bag: bag)
        XCTAssertEqual(second.itemCount, 1)
        XCTAssertEqual(second.collections.first?.isNameResolved, false)
        let failedUpdate = expectation(description: "catalog failure handled")
        provider.updatesObservable.take(1).subscribe(onNext: { _ in failedUpdate.fulfill() }).disposed(by: bag)
        await insight.finishCatalog(.failure(SRC721InsightError.invalidResponse))
        await fulfillment(of: [failedUpdate], timeout: 3)
        XCTAssertEqual(provider.localPayload(address: owner, account: account)?.collections.first?.isNameResolved, false)

        let finalUpdate = expectation(description: "new collection name applied")
        provider.updatesObservable.take(1).subscribe(onNext: { _ in finalUpdate.fulfill() }).disposed(by: bag)
        await insight.setCount(2)
        let latest = try await load(provider, account: account, bag: bag)
        XCTAssertEqual(latest.itemCount, 2)
        await insight.finishCatalog(.success([SRC721InsightToken(
            address: contract, name: "New NFT", symbol: "NFT", type: "erc721",
            logoURI: "https://example.com/logo.png", template: false, creator: owner
        )]))
        await fulfillment(of: [finalUpdate], timeout: 3)
        let resolved = try XCTUnwrap(provider.localPayload(address: owner, account: account)?.collections.first)
        XCTAssertEqual(resolved.name, "New NFT")
        XCTAssertTrue(resolved.isNameResolved)
        XCTAssertEqual(resolved.count, 2)
        XCTAssertEqual(resolved.imageUrl, "https://example.com/logo.png")
        let assetRequests = await insight.assetRequestCount
        XCTAssertEqual(assetRequests, 0)
        let catalogRequests = await insight.catalogRequestCount
        XCTAssertEqual(catalogRequests, 3)
    }

    func testLocalSafeZoneNameIsAvailableWhileCatalogIsPending() async throws {
        let suite = "safe4-nft-local-name-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let account = try makeAccount()
        let storage = SRC721Storage(defaults: defaults)
        storage.save(contract: SRC721ContractRecord(
            accountId: account.id, chainId: Safe4Network.currentChainId, walletAddress: owner,
            contractAddress: contract, predictedContractAddress: nil, creatorAddress: owner,
            currentOwnerAddress: owner, contractType: .standard, name: "Local NFT", symbol: "NFT",
            baseURI: "", maxSupply: "100", mintPrice: "0", deployTransactionHash: nil,
            transactionStatus: .confirmed, validationStatus: "", createdAt: Date()
        ))
        let insight = ControlledNftInsight(owner: owner, contract: contract)
        let provider = NftV2Safe4InventoryProvider(
            addressMetadata: { _ in nil }, marketProvider: NftV2MarketProvider(),
            contractStorage: storage, insightProviderFactory: { _ in insight }
        )
        let bag = DisposeBag()
        let payload = try await load(provider, account: account, bag: bag)
        XCTAssertEqual(payload.collections.first?.name, "Local NFT")
        XCTAssertEqual(payload.collections.first?.isNameResolved, true)
        await insight.finishCatalog(.success([]))
    }

    private func makeAccount() throws -> Account {
        Account(id: UUID().uuidString, level: 0, name: "Test", type: .evmAddress(address: try EvmKit.Address(hex: owner)),
                origin: .restored, backedUp: true, fileBackedUp: false)
    }

    private func load(_ provider: NftV2Safe4InventoryProvider, account: Account, bag: DisposeBag) async throws -> NftV2InventoryPayload {
        try await withCheckedThrowingContinuation { continuation in
            provider.load(address: owner, account: account)
                .subscribe(onSuccess: { continuation.resume(returning: $0) }, onError: { continuation.resume(throwing: $0) })
                .disposed(by: bag)
        }
    }
}

private actor ControlledNftInsight: SRC721InsightAssetProvider {
    let owner: String
    let contract: String
    private var count = 1
    private var pendingCatalog: CheckedContinuation<[SRC721InsightToken], Error>?
    private var queuedCatalog: Result<[SRC721InsightToken], Error>?
    private(set) var catalogRequestCount = 0
    private(set) var assetRequestCount = 0

    init(owner: String, contract: String) {
        self.owner = owner
        self.contract = contract
    }

    func setCount(_ count: Int) { self.count = count }

    func tokens() async throws -> [SRC721InsightToken] {
        catalogRequestCount += 1
        if let result = queuedCatalog {
            queuedCatalog = nil
            return try result.get()
        }
        return try await withCheckedThrowingContinuation { pendingCatalog = $0 }
    }

    func finishCatalog(_ result: Result<[SRC721InsightToken], Error>) {
        if let continuation = pendingCatalog {
            pendingCatalog = nil
            continuation.resume(with: result)
        } else {
            queuedCatalog = result
        }
    }

    func holdings(owner: String) async throws -> [SRC721InsightHolding] {
        let data = Data("[{\"owner\":\"\(owner)\",\"token\":\"\(contract)\",\"count\":\"\(count)\"}]".utf8)
        return try JSONDecoder().decode([SRC721InsightHolding].self, from: data)
    }

    func assets(owner: String, tokenAddress: String) async throws -> [SRC721InsightAsset] {
        assetRequestCount += 1
        return []
    }
}
