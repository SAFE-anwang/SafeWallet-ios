import UIKit
import MarketKit
import SwiftUI

struct LineLockRecoardModule {
    
    static func viewModel() -> LineLockRecoardViewModel? {
        guard let wallet = Core.shared.walletManager.activeWallets.filter({ $0.coin.uid == safeCoinUid && $0.token.blockchain.type == .safe }).first else {
            HudHelper.instance.show(banner: .error(string: "safe_zone.send.openCoin".localized("SAFE")))
            return nil
        }
        guard let account = Core.shared.accountManager.activeAccount else { return nil }
        guard let state = WalletAdapterService(account: account, adapterManager: Core.shared.adapterManager).state(wallet: wallet), state == .synced else {
            HudHelper.instance.show(banner: .error(string: "balance.syncing".localized))
            return nil
        }
        guard let adapter = Core.shared.adapterManager.adapter(for: wallet) as? SafeCoinAdapter else { return nil }

        let viewModel = LineLockRecoardViewModel(wallet: wallet, adapter: adapter)
        return viewModel
    }
}

struct LineLockRecoardView: UIViewControllerRepresentable {
    typealias UIViewControllerType = UIViewController
    let viewModel: LineLockRecoardViewModel
    @Binding var isPresented: Bool
    
    func makeUIViewController(context _: Context) -> UIViewController {
        let viewController = LineLockRecoardViewController(viewModel: viewModel)
        let navigationController = ThemeNavigationController(rootViewController: viewController)
        viewController.onDismiss = {
            isPresented = false
        }
        return navigationController
    }

    func updateUIViewController(_: UIViewController, context _: Context) {}
    
}
