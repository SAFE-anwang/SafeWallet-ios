import EvmKit
import Foundation
import MarketKit
import SwiftUI
import Testing
import UIKit
@testable import WalletCore

// Opt-in because this exercises the real application model and an isolated, empty app store.
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SAFEWALLET_REFRESH_UI_TEST"] == "1"))
struct WalletRefreshPresentationTests {
    @Test func refreshUpdatesKeepWalletListPosition() async throws {
        let accounts = Core.shared.accountManager
        try #require(accounts.accounts.isEmpty, "Run only in an empty, dedicated simulator")
        let account = Account(id: UUID().uuidString, level: accounts.currentLevel, name: "Refresh fixture",
                              type: .evmAddress(address: try EvmKit.Address(hex: "0x0000000000000000000000000000000000000001")),
                              origin: .restored, backedUp: true, fileBackedUp: false)
        accounts.save(account: account)
        defer { accounts.delete(account: account) }
        await Core.shared.walletManager.preloadWalletsAndWait()
        let model = WalletViewModel()
        let oldSort = model.sortType
        model.sortType = .name
        defer { model.sortType = oldSort }

        // No tokens are persisted or enabled. Supply deterministic adapter events only.
        let items: [WalletListViewModel.Item] = (0..<24).map { index in
            let name = String(format: "Fixture %02d", index)
            let token = Token(coin: Coin(uid: "refresh-fixture-\(index)", name: name, code: "T\(index)"),
                              blockchain: Blockchain(type: .ethereum, name: "Ethereum", explorerUrl: nil),
                              type: .eip20(address: String(format: "0x%040x", index + 1)), decimals: 18)
            return .init(wallet: Wallet(token: token, account: account), isMainNet: true,
                         balanceData: BalanceData(balance: Decimal(index + 1)), caution: nil, state: .synced)
        }
        model.queue.sync {
            model.__items = items
        }
        model.didUpdate(state: .synced, wallet: items[0].wallet)
        try await settle()
        try #require(model.items.count == items.count && !model.noTokens)

        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let controller = UIHostingController(rootView: ThemeNavigationStack {
            WalletView(viewModel: model, selectedWallet: .constant(nil))
        }.environment(\.colorScheme, .light))
        window.rootViewController = controller
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        try await settle()
        let list = try #require(descendants(controller.view).compactMap { $0 as? UICollectionView }.first)
        list.setContentOffset(CGPoint(x: 0, y: 520), animated: false)
        try await settle()
        let initialOffset = list.contentOffset.y
        let initialIDs = model.items.map(\.id)
        var samples = [initialOffset]

        for state: AdapterState in [.syncing(progress: 0, remaining: nil, lastBlockDate: nil),
                                    .syncing(progress: 50, remaining: nil, lastBlockDate: nil), .synced] {
            for item in items { model.didUpdate(state: state, wallet: item.wallet) }
            for _ in 0..<30 {
                try await Task.sleep(for: .milliseconds(16))
                samples.append(list.contentOffset.y)
            }
            #expect(model.items.map(\.id) == initialIDs)
            #expect(model.items.allSatisfy { $0.state == state }, "Stable identity must not suppress status updates")
        }
        let maximumShift = samples.map { abs($0 - initialOffset) }.max() ?? 0
        let report: [String: Any] = ["initialOffset": initialOffset, "maximumShift": maximumShift,
                                     "offsets": samples, "itemCount": model.items.count]
        if #available(iOS 26.0, *) {
            Attachment.record(try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted]), named: "wallet-refresh-offsets.json")
            let png = UIGraphicsImageRenderer(bounds: controller.view.bounds).pngData { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
            Attachment.record(png, named: "wallet-after-refresh-events.png")
        }
        #expect(maximumShift <= 1, "Status-only refresh events must not move the unchanged wallet list")
    }

    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(500))
    }

    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
