import BigInt
import Foundation
import Web3Core
import web3swift
import XCTest
@testable import WalletCore

final class MarketDappVisibilityTests: XCTestCase {
    func testOnlyOwnedOrPromotedDappsAreVisible() {
        let items = [
            item(id: 1, logo: nil),
            item(id: 2, logo: Data([1])),
            item(id: 3, logo: nil),
            item(id: 4, logo: Data([1])),
            item(id: 5, logo: Data()),
        ]

        let result = MarketDappService.marketDapps(from: items, mineIDs: [1, 2])

        XCTAssertEqual(result.compactMap(\.safeDappId), [1, 2, 4])
        XCTAssertEqual(result.last?.safeDappLogoData, Data([1]))
    }

    func testUnownedDappWaitsForLogoBeforeBecomingVisible() {
        XCTAssertTrue(MarketDappService.marketDapps(from: [item(id: 1, logo: nil)], mineIDs: []).isEmpty)
        XCTAssertEqual(
            MarketDappService.marketDapps(from: [item(id: 1, logo: Data([1]))], mineIDs: []).compactMap(\.safeDappId),
            [1]
        )
    }

    func testOwnershipIsScopedToCurrentWallet() {
        let items = [item(id: 1, logo: nil), item(id: 2, logo: nil), item(id: 3, logo: Data([1]))]

        XCTAssertEqual(MarketDappService.marketDapps(from: items, mineIDs: [1]).compactMap(\.safeDappId), [1, 3])
        XCTAssertEqual(MarketDappService.marketDapps(from: items, mineIDs: [2]).compactMap(\.safeDappId), [2, 3])
        XCTAssertEqual(MarketDappService.marketDapps(from: items, mineIDs: []).compactMap(\.safeDappId), [3])
    }

    private func item(id: BigUInt, logo: Data?) -> SafeDappPublishedItem {
        let address = EthereumAddress("0x1111111111111111111111111111111111111111")!
        let info = DAppInfo(
            id: id, name: "DApp \(id)", contractAddr: address, runUrl: "https://example.org/\(id)",
            gitUrl: "", officialUrl: "", officialEmail: "", officialAccount: address,
            description: "Example DApp", keyword: "", fraudNum: 0, isFrozen: false
        )
        return SafeDappPublishedItem(info: info, logoData: logo)
    }
}
