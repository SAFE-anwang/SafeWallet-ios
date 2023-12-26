import RxSwift
import RxRelay
import RxCocoa
import SafeCoinKit
import Checkpoints
import Combine
class FallbackBlockViewModel {
    
    private let disposeBag = DisposeBag()
    
    private let walletManager: WalletManager
    private let accountManager: AccountManager
    private let adapterManager: AdapterManager

    lazy var fallbackBlockViewItems: [FallbackBlockViewItem] = {
        let item0 = FallbackBlockViewItem(date: .date_202312, item: SelectorModule.ViewItem(title: "safe_setting.fallbackBlock".localized("5400104（2023-12）"), selected: false))
        let item1 = FallbackBlockViewItem(date: .date_202309, item: SelectorModule.ViewItem(title: "safe_setting.fallbackBlock".localized("5178101（2023-9）"), selected: false))
        let item2 = FallbackBlockViewItem(date: .date_202306, item: SelectorModule.ViewItem(title: "safe_setting.fallbackBlock".localized("4939318（2023-6）"), selected: false))
        let item3 = FallbackBlockViewItem(date: .date_202304, item: SelectorModule.ViewItem(title: "safe_setting.fallbackBlock".localized("4656085（2023-4）"), selected: false))
//        let item4 = FallbackBlockViewItem(date: .date_202302, item: SelectorModule.ViewItem(title: "safe_setting.fallbackBlock".localized("4581517（2023-2）"), selected: false))
        return [item0, item1, item2, item3]
    }()
    
    init(walletManager: WalletManager, accountManager: AccountManager, adapterManager: AdapterManager) {
        self.walletManager = walletManager
        self.accountManager = accountManager
        self.adapterManager = adapterManager
    }
    
    func fallbackBlock(item: FallbackBlockViewItem) {
        guard let wallet = walletManager.activeWallets.first(where: { $0.token.type == .native && $0.token.coin.uid == safeCoinUid } ) else { return }
        if let adapter = adapterManager.adapter(for: wallet) as? SafeCoinAdapter {
            adapter.fallbackBlock(date: item.date)
            adapterManager.preloadAdapters()
        }
    }
    
}

extension FallbackBlockViewModel {
    struct FallbackBlockViewItem {
        let date: CheckpointData.FallbackDate
        let item: SelectorModule.ViewItem
        
    }
}
