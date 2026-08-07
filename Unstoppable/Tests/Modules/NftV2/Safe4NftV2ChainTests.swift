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
}
