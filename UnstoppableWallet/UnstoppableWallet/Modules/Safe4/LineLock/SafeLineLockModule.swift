import UIKit
import MarketKit
import ComponentKit
import SwiftUI
import ThemeKit

struct SafeLineLockModule {
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
        guard let adapter = App.shared.adapterManager.adapter(for: wallet) as? EvmAdapter else {
            return nil
        }

        let viewModel = SafeLineLockViewModel(wallet: wallet, account: account, adapter: adapter)
        let viewController = SafeLineLockView(viewModel: viewModel).toViewController()
        viewController.hidesBottomBarWhenPushed = true
        return viewController
    }
}
