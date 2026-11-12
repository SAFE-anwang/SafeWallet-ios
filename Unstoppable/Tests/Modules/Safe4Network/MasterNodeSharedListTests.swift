import BigInt
import Web3Core
import web3swift
import XCTest
@testable import WalletCore

final class MasterNodeSharedListTests: XCTestCase {
    @MainActor
    func testBothListsProjectTheSameLoadedPages() {
        let unit = BigUInt(10).power(18)
        let firstPage = [item(id: 4, amounts: [1000 * unit]), item(id: 3, amounts: [200 * unit])]
        XCTAssertEqual(MasterNodeViewModel.displayItems(firstPage, crowdfundingOnly: false).map(\.id), ["4", "3"])
        XCTAssertEqual(MasterNodeViewModel.displayItems(firstPage, crowdfundingOnly: true).map(\.id), ["3"])

        let loaded = firstPage + [item(id: 2, amounts: [400 * unit, 500 * unit]), firstPage[1]]
        XCTAssertEqual(MasterNodeViewModel.displayItems(loaded, crowdfundingOnly: false).map(\.id), ["4", "3", "2"])
        XCTAssertEqual(MasterNodeViewModel.displayItems(loaded, crowdfundingOnly: true).map(\.id), ["2", "3"])
    }

    @MainActor
    func testCrowdfundingBoundaryAndSearchProjection() {
        let threshold = BigUInt(1000) * BigUInt(10).power(18)
        let items = [item(id: 1, amounts: [threshold - 1]), item(id: 2, amounts: [threshold]), item(id: 3, amounts: [threshold + 1])]
        XCTAssertEqual(MasterNodeViewModel.displayItems(items, crowdfundingOnly: true).map(\.id), ["1"])
        XCTAssertTrue(MasterNodeViewModel.displayItems([items[1]], crowdfundingOnly: true).isEmpty)
        XCTAssertEqual(MasterNodeViewModel.displayItems([items[1]], crowdfundingOnly: false).map(\.id), ["2"])
    }

    private func item(id: UInt64, amounts: [BigUInt]) -> MasterNodeViewModel.ViewItem {
        let address = EthereumAddress("0x0000000000000000000000000000000000000001")!
        let info = MasterNodeInfo(
            id: BigUInt(id), addr: address, creator: address, enode: "", description: "", isOfficial: false,
            state: 0, founders: amounts.map { MasterNodeMemberInfo(lockID: 1, addr: address, amount: $0, unlockHeight: 0) },
            incentivePlan: MasterNodeIncentivePlan(creator: 0, partner: 0, voter: 0), isUnion: false,
            lastRewardHeight: 0, createHeight: 0, updateHeight: 0
        )
        return MasterNodeViewModel.ViewItem(info: info, isNodeAddress: false, isEnabledEdit: false, ownerType: .None)
    }
}
