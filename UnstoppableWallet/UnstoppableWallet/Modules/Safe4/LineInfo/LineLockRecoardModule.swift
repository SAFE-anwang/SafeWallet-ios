import UIKit
import MarketKit
import ComponentKit

struct LineLockRecoardModule {

    static func viewController() -> UIViewController? {
        guard let wallet = App.shared.walletManager.activeWallets.filter({ $0.coin.uid == safeCoinUid && $0.token.blockchain.type == .safe }).first else { return nil }
        guard let adapter = App.shared.adapterManager.adapter(for: wallet) as? SafeCoinAdapter else { return nil }
        guard let account = App.shared.accountManager.activeAccount else { return nil }
        guard let state = WalletAdapterService(account: account, adapterManager: App.shared.adapterManager).state(wallet: wallet), state == .synced else {
            HudHelper.instance.show(banner: .error(string: "balance.syncing".localized))
            return nil
        }
        let viewModel = LineLockRecoardViewModel(wallet: wallet, adapter: adapter)

        return LineLockRecoardViewController(lineLockRecoardViewModel: viewModel)
    }

}
