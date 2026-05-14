import Foundation
import UIKit
import Combine
import MarketKit
import SafeCoinKit
import BitcoinCore
import HsToolKit
import HdWalletKit

class LineLockRecoardViewModel: ObservableObject {
    @Published var viewItems: [ViewItem] = []
    @Published var lockedBalanceTitle: String = ""
    @Published var isLoading: Bool = true
    @Published var errorMessage: String?
    
    private let coinRate: Decimal = pow(10, 8)
    
    private let wallet: Wallet
    private let adapter: SafeCoinAdapter
    
    init(wallet: Wallet, adapter: SafeCoinAdapter) {
        self.wallet = wallet
        self.adapter = adapter
        
        Task {
            await syncData()
        }
    }
    
    private func syncData() async {
        guard wallet.coin.uid == safeCoinUid && wallet.token.blockchain.type == .safe else {
            await MainActor.run { isLoading = false }
            return
        }
        guard let account = Core.shared.accountManager.activeAccount else {
            await MainActor.run { isLoading = false }
            return
        }
        
        let service = WalletAdapterService(account: account, adapterManager: Core.shared.adapterManager)
        let state = service.state(wallet: wallet)
        
        if state == .synced {
            let lockedBalanceData = adapter.balanceData
            let lockUxto = adapter.safeCoinKit.getConfirmedUnspentOutputProvider().getLockUxto()
            let (items, lockedValue) = await Task.detached { [weak self] in
                guard let self = self else { return ([ViewItem](), Decimal.zero) }
                return self.syncLockedRecordItemsOnBackground(items: lockUxto)
            }.value
            
            let title = "safe_lock.recoard.title".localized("\(lockedBalanceData.locked + lockedValue)")
            
            await MainActor.run {
                self.viewItems = items
                self.lockedBalanceTitle = title
                self.isLoading = false
            }
        } else {
            await MainActor.run { isLoading = false }
        }
    }
    
    private func syncLockedRecordItemsOnBackground(items: [UnspentOutput]) -> ([ViewItem], Decimal) {
        let lastHeight: Int = adapter.lastBlockInfo?.height ?? 0
        var totalLockedValue: Decimal = 0
        var tempViewItems: [ViewItem] = []
        
        for item in items {
            let height: Int = item.blockHeight ?? lastHeight
            if let unlockedHeight = item.output.unlockedHeight {
                let lockAmount = (Decimal(item.output.value) / coinRate)
                totalLockedValue += lockAmount
                let lockMonth = (unlockedHeight - height) / 86300
                let isLocked = lastHeight <= unlockedHeight
                let viewItem = ViewItem(
                    height: height,
                    lockAmount: lockAmount.formattedAmount,
                    lockMonth: lockMonth,
                    isLocked: isLocked,
                    address: item.output.address ?? ""
                )
                tempViewItems.append(viewItem)
            }
        }
        
        let sortedItems = tempViewItems.sorted(by: descending)
        return (sortedItems, totalLockedValue)
    }
    
    private let descending: (ViewItem, ViewItem) -> Bool = { lhsItem, rhsItem in
        if lhsItem.height == rhsItem.height {
            return lhsItem.lockMonth < rhsItem.lockMonth
        }
        return lhsItem.height > rhsItem.height
    }
    
    func copyAddress(_ address: String) {
        UIPasteboard.general.string = address
        HudHelper.instance.show(banner: .copied)
    }
    
    struct ViewItem: Identifiable, Equatable {
        let id = UUID()
        let height: Int
        let lockAmount: String
        let lockMonth: Int
        let isLocked: Bool
        let address: String
    }
}

extension Decimal {
    private static let amountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesSignificantDigits = true
        formatter.usesGroupingSeparator = false
        return formatter
    }()
    
    var formattedAmount: String {
        Self.amountFormatter.string(from: self as NSDecimalNumber) ?? "0"
    }
}
