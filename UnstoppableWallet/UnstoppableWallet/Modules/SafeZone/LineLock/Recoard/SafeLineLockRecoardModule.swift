import UIKit
import MarketKit
import SwiftUI

struct SafeLineLockRecoardModule {

    static func viewModel() -> SafeLineLockRecoardViewModel? {
        guard let wallet = Core.shared.walletManager.activeWallets.filter({ $0.coin.uid == safe4CoinUid && $0.token.blockchain.type == .safe4  && $0.token.type == .native}).first else {
            HudHelper.instance.show(banner: .error(string: "safe_zone.send.openCoin".localized("SAFE")))
            return nil
        }
        guard let account = Core.shared.accountManager.activeAccount else {
            return nil
        }
        
        guard let state = WalletAdapterService(account: account, adapterManager: Core.shared.adapterManager).state(wallet: wallet), state == .synced else {
            HudHelper.instance.show(banner: .error(string: "transactions.syncing_placeholder".localized))
            return nil
        }
        let vm = TransactionsViewModel(transactionFilter: .init(token: wallet.token))
        vm.typeFilter = .outgoing
        let viewModel = SafeLineLockRecoardViewModel(tsVM: vm)
        return viewModel
    }
}
