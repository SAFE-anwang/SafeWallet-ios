import RxSwift
import RxRelay
import RxCocoa
import SafeCoinKit
import Checkpoints
import Combine
import MarketKit

class FallbackBlockViewModel {
    
    private let disposeBag = DisposeBag()
    
    private let walletManager: WalletManager
    private let accountManager: AccountManager
    private let adapterManager: AdapterManager

    lazy var fallbackBlockViewItems: [FallbackBlockViewItem] = {
        let item0 = FallbackBlockViewItem(date: .date_202403, item: SelectorModule.ViewItem(title: "safe_setting.fallbackBlock".localized("5639934（2024-03）"), selected: false))
        let item1 = FallbackBlockViewItem(date: .date_202312, item: SelectorModule.ViewItem(title: "safe_setting.fallbackBlock".localized("5400104（2023-12）"), selected: false))
        let item2 = FallbackBlockViewItem(date: .date_202309, item: SelectorModule.ViewItem(title: "safe_setting.fallbackBlock".localized("5178101（2023-9）"), selected: false))
        return [item0, item1, item2]
    }()
    
    init(walletManager: WalletManager, accountManager: AccountManager, adapterManager: AdapterManager) {
        self.walletManager = walletManager
        self.accountManager = accountManager
        self.adapterManager = adapterManager
    }
    
    func fallbackBlock(item: FallbackBlockViewItem) {
        guard let wallet = walletManager.activeWallets.first(where: { $0.token.type == .native && $0.token.coin.uid == safeCoinUid } ) else { return }
        if let adapter = adapterManager.depositAdapter(for: wallet) as? SafeCoinAdapter {
            adapter.fallbackBlock(date: item.date)
//            adapterManager.preloadAdapters()
//            refreshWallet(wallet)
        }
    }
    
//    func refreshWallet(_ wallet: Wallet) {
//        adapterManager.refresh(wallet: wallet)
//    }
    
}

extension FallbackBlockViewModel {
    struct FallbackBlockViewItem {
        let date: CheckpointData.FallbackDate
        let item: SelectorModule.ViewItem
        
    }
}
