import UIKit
import MarketKit
import SwiftUI

struct SafeLineLockRecoardModule {

    static func viewModel() -> SafeLineLockRecoardViewModel? {
        guard let wallet = Core.shared.walletManager.activeWallets.filter({ $0.coin.uid == safe4CoinUid && $0.token.blockchain.type == .safe4 }).first else {
            HudHelper.instance.show(banner: .error(string: "safe_zone.send.openCoin".localized("SAFE")))
            return nil
        }
        guard let adapter = Core.shared.adapterManager.adapter(for: wallet) as? EvmAdapter else {
            return nil
        }
        adapter.evmKit.transactionsObservable(tagQueries: [])
//        let transactionsViewModel = TransactionsViewModel(transactionFilter: .init(token: wallet.token))
        let viewModel = SafeLineLockRecoardViewModel(adapter:  adapter as! ITransactionsAdapter)

        return viewModel
    }
}
