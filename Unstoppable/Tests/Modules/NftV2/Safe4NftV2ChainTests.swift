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

    @Test func safe4InsightDiscoveryDeduplicatesContractsAndSkipsEmptyHoldings() throws {
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

        #expect(requests.count == 1)
        #expect(requests.first?.key == "0x0000000000000000000000000000000000000001")
        #expect(NftV2Safe4InventoryProvider.maxConcurrentContractRequests == 4)
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
