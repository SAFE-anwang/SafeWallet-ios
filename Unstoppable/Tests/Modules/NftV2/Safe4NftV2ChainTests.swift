import Foundation
import Testing
import MarketKit
import NftKit
@testable import WalletCore

struct Safe4NftV2ChainTests {
    @Test func safe4ParticipatesInNftV2AsEip721Chain() {
        #expect(NftV2Chain.allCases.contains(.safe4))
        #expect(NftV2Chain.safe4.blockchainType == .safe4)
        #expect(BlockchainType.safe4.supportedNftTypes == [.eip721])
        #expect(NftV2MarketProvider().primaryMarket(chain: .safe4) == nil)
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
        #expect(NftV2Safe4InventoryProvider.maxConcurrentContractRequests == 4)
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

    @Test func safe4AssetLookupKeepsSuccessfulContractsWhenAnotherContractFails() async throws {
        let owner = "0x4c207825db1c46dd836123e58ecae85de7025879"
        let firstContract = "0x0000000000000000000000000000000000000001"
        let secondContract = "0x0000000000000000000000000000000000000002"
        let data = """
        [{"owner":"\(owner)","token":"\(firstContract)","tokenType":"erc721","tokenId":7,"tokenValue":1,"tokenURI":null,"tokenImage":null}]
        """.data(using: .utf8)!
        let assets = try JSONDecoder().decode([SRC721InsightAsset].self, from: data)
        let insight = MockSRC721InsightProvider(successfulContract: firstContract, assets: assets)

        let result = await NftV2Safe4InventoryProvider.fetchAssets(
            requests: [(firstContract, firstContract), (secondContract, secondContract)],
            owner: owner,
            insight: insight
        )

        #expect(result.assetsByContract[firstContract]?.count == 1)
        #expect(result.failedContractKeys == [secondContract])
        #expect(!result.isComplete)
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

private final class MockSRC721InsightProvider: SRC721InsightAssetProvider {
    private let successfulContract: String
    private let result: [SRC721InsightAsset]

    init(successfulContract: String, assets: [SRC721InsightAsset]) {
        self.successfulContract = successfulContract
        result = assets
    }

    func tokens() async throws -> [SRC721InsightToken] { [] }
    func holdings(owner _: String) async throws -> [SRC721InsightHolding] { [] }

    func assets(owner _: String, tokenAddress: String) async throws -> [SRC721InsightAsset] {
        guard tokenAddress.caseInsensitiveCompare(successfulContract) == .orderedSame else {
            throw URLError(.badServerResponse)
        }
        return result
    }
}
