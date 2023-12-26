import Foundation
import RxSwift
import RxCocoa
import CurrencyKit
import MarketKit
import SafeCoinKit
import BitcoinCore
import HsToolKit
import HdWalletKit

class LineLockRecoardViewModel {
    private let disposeBag = DisposeBag()
    private let coinRate: Decimal = pow(10, 8)
    
    private let wallet: Wallet
    private let adapter: SafeCoinAdapter

    public var lockedBalanceTitle: String?
    
    private var viewItemsRelay = BehaviorRelay<[ViewItem]>(value: [])
    
    private var viewItems = [ViewItem]()
    
    init(wallet: Wallet, adapter: SafeCoinAdapter) {
        self.wallet = wallet
        self.adapter = adapter
        
        guard wallet.coin.uid == safeCoinUid  && wallet.token.blockchain.type == .safe else { return }
        guard let account = App.shared.accountManager.activeAccount else { return }
        if let state = WalletAdapterService(account: account, adapterManager: App.shared.adapterManager).state(wallet: wallet), state == .synced {
            if let lockedBalanceData = adapter.balanceData as? LockedBalanceData {
                let title = "safe_lock.recoard.title".localized("\(lockedBalanceData.locked)")
                lockedBalanceTitle = title
            }
            let lockUxto = adapter.safeCoinKit.getConfirmedUnspentOutputProvider().getLockUxto()
            syncLockedRecordItems(items: lockUxto)
        }
    }
    
    private func syncLockedRecordItems(items: [UnspentOutput]) {
        
        let lastHeight: Int = adapter.lastBlockInfo?.height ?? 0
        
        for item in items {
            var height: Int = 0
            if let h = item.blockHeight {
                height = h
            }else {
                 height = lastHeight
            }
            if let unlockedHeight = item.output.unlockedHeight {
                let lockAmount = "\((Decimal(item.output.value) / coinRate).formattedAmount)"
                let lockMonth = (unlockedHeight - height) / 86300
                let isLocked = lastHeight <= unlockedHeight
                let viewItem = ViewItem(height: height, lockAmount: lockAmount, lockMonth: lockMonth, isLocked: isLocked, address: item.output.address ?? "")
                viewItems.append(viewItem)
            }
        }
        viewItemsRelay.accept(viewItems.sorted(by: descending))
    }
    
    private let descending: (ViewItem, ViewItem) -> Bool = { lhsItem, rhsItem in
        let lhsHeight = lhsItem.height
        let rhsHeight = rhsItem.height
        let lhsLockMonth = lhsItem.lockMonth
        let rhsLockMonth = rhsItem.lockMonth

        if lhsHeight == rhsHeight {
            return lhsLockMonth < rhsLockMonth
        }

        return lhsHeight > rhsHeight
    }

}

extension LineLockRecoardViewModel {
    
    
    var viewItemsDriver: Driver<[ViewItem]> {
        viewItemsRelay.asDriver()
    }
    
    struct ViewItem {
        let height: Int
        let lockAmount: String
        let lockMonth: Int
        let isLocked: Bool
        let address: String
    }
}

extension Decimal {
    var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesSignificantDigits = true
        formatter.usesGroupingSeparator = false
        return formatter.string(from: self as NSDecimalNumber)!
    }
}
