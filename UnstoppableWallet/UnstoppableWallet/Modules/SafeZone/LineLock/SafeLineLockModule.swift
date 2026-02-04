import UIKit
import MarketKit
import SwiftUI

struct SafeLineLockModule {

    static func viewModel() -> SafeLineLockViewModel? {
        guard let wallet = Core.shared.walletManager.activeWallets.filter({ $0.coin.uid.isSafeCoin && $0.token.blockchain.type == .safe4 }).first else {
            HudHelper.instance.show(banner: .error(string: "safe_zone.send.openCoin".localized("SAFE")))
            return nil
        }
        guard let account = Core.shared.accountManager.activeAccount else {
            return nil
        }
        
        guard let state = WalletAdapterService(account: account, adapterManager: Core.shared.adapterManager).state(wallet: wallet), state == .synced else {
            HudHelper.instance.show(banner: .error(string: "balance.syncing".localized))
            return nil
        }
        guard let adapter = Core.shared.adapterManager.adapter(for: wallet) as? EvmAdapter else {
            return nil
        }

        let viewModel = SafeLineLockViewModel(wallet: wallet, account: account, adapter: adapter)
        return viewModel
    }
}
