import UIKit
import MarketKit
import ComponentKit
import SwiftUI
import ThemeKit

struct SafeLineLockRecoardModule {
    static func viewController() -> UIViewController? {
        guard let wallet = App.shared.walletManager.activeWallets.filter({ $0.coin.uid == safe4CoinUid && $0.token.blockchain.type == .safe4 }).first else {
            HudHelper.instance.show(banner: .error(string: "safe_zone.send.openCoin".localized("SAFE")))
            return nil
        }
        guard let account = App.shared.accountManager.activeAccount else {
            return nil
        }
        
        guard let state = WalletAdapterService(account: account, adapterManager: App.shared.adapterManager).state(wallet: wallet), state == .synced else {
            HudHelper.instance.show(banner: .error(string: "balance.syncing".localized))
            return nil
        }

        let rateService = HistoricalRateService(marketKit: App.shared.marketKit, currencyManager: App.shared.currencyManager)
        let nftMetadataService = NftMetadataService(nftMetadataManager: App.shared.nftMetadataManager)
        let service = TokenTransactionsService(
            token: wallet.token,
            adapterManager: App.shared.transactionAdapterManager,
            rateService: rateService,
            nftMetadataService: nftMetadataService
        )
        let contactLabelService = TransactionsContactLabelService(contactManager: App.shared.contactManager)
        let viewItemFactory = TransactionsViewItemFactory(evmLabelManager: App.shared.evmLabelManager, contactLabelService: contactLabelService)

        let viewModel = SafeLineLockRecoardViewModel(service: service, factory: viewItemFactory)
        let viewController = SafeLineLockRecoardView(viewModel: viewModel).toViewController()
        viewController.hidesBottomBarWhenPushed = true
        return viewController
    }
}
