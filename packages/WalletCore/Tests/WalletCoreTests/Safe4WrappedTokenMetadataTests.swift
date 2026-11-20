import MarketKit
import XCTest
@testable import WalletCore

final class Safe4WrappedTokenMetadataTests: XCTestCase {
    private let address = "0x0000000000000000000000000000000000001101"

    private func token(blockchainType: BlockchainType = .safe4, type: TokenType? = nil, code: String = "SAFE", name: String = "SAFE") -> Token {
        let type = type ?? .eip20(address: address)
        return Token(
            coin: Coin(
                // Both imported modules define customCoinUid; keep the persisted UID format in this fixture.
                uid: "custom-\(TokenQuery(blockchainType: blockchainType, tokenType: type).id)",
                name: name,
                code: code,
                marketCapRank: 123,
                coinGeckoId: "existing-price-id",
                image: "existing-image"
            ),
            blockchain: Blockchain(type: blockchainType, name: "Chain", explorerUrl: nil),
            type: type,
            decimals: 18
        )
    }

    func testLegacyEnabledTokenKeepsWSAFENameAndAssetIdentity() {
        // Matches the phone's MarketKit and enabled-wallet records: SAFE / SAFE.
        let legacy = token()
        let resolved = legacy.withCanonicalSafe4Metadata

        XCTAssertEqual(resolved.coin.code, "WSAFE")
        XCTAssertEqual(resolved.coin.name, "Wrapped SAFE")
        XCTAssertEqual(resolved.tokenQuery.id, legacy.tokenQuery.id)
        XCTAssertEqual(resolved.coin.uid, legacy.coin.uid)
        XCTAssertEqual(resolved.decimals, legacy.decimals)
        XCTAssertEqual(resolved.coin.image, legacy.coin.image)
        XCTAssertEqual(resolved.coin.coinGeckoId, legacy.coin.coinGeckoId)
        XCTAssertEqual(resolved.coin.marketCapRank, legacy.coin.marketCapRank)
        XCTAssertEqual(resolved, legacy)
    }

    func testEnabledTokenWinningDeduplicationStillDisplaysWSAFE() {
        let preferred = token().withCanonicalSafe4Metadata
        let directory = token(code: "WSAFE", name: "Wrapped SAFE")
        var seen = Set<Token>()
        let list = [preferred, directory].filter { seen.insert($0).inserted }

        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.coin.code, "WSAFE")
        XCTAssertTrue(preferred.coin.code.lowercased().contains("wsafe"))
    }

    func testNativeSAFEAndOtherContractsAndChainsAreUnchanged() {
        let unaffected = [
            token(type: .native),
            token(type: .eip20(address: "0x0000000000000000000000000000000000001102")),
            token(blockchainType: .ethereum),
        ]
        for original in unaffected {
            XCTAssertTrue(original.withCanonicalSafe4Metadata.coin === original.coin)
            XCTAssertEqual(original.withCanonicalSafe4Metadata.coin.code, "SAFE")
        }
    }

    func testCorrectMetadataIsReused() {
        let correct = token(code: "WSAFE", name: "Wrapped SAFE")
        XCTAssertTrue(correct.withCanonicalSafe4Metadata.coin === correct.coin)
    }
}
