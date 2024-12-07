import UIKit
import EvmKit
import MarketKit
import ComponentKit

struct RedeemSafe3Module {
    
    static func viewController() -> UIViewController? {
        let walletList = App.shared.walletManager.activeWallets
        var safe4Wallet: Wallet?
        
        for wallet in walletList {
            if wallet.coin.uid == safe4CoinUid {
                if wallet.token.blockchain.type == .safe4 {
                    safe4Wallet = wallet
                }
            }
        }
        
        guard let safe4Wallet else {
            HudHelper.instance.show(banner: .error(string: "safe_zone.send.openCoin".localized("SAFE4")))
            return nil
        }
        guard let account = App.shared.accountManager.activeAccount else { return nil }
        
        guard let state = WalletAdapterService(account: account, adapterManager: App.shared.adapterManager).state(wallet: safe4Wallet), state == .synced else {
            HudHelper.instance.show(banner: .error(string: "SAFE4" + "balance.syncing".localized))
            return nil
        }
        
        guard let safe4EvmKitWrapper = App.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            return nil
        }

        let  viewModel = RedeemSafe3TabViewModel()
        return RedeemSafe3TabViewController(account: account, viewModel: viewModel, safe4EvmKitWrapper: safe4EvmKitWrapper)
    }
    
    static func subViewController(account: Account, safe4EvmKitWrapper: EvmKitWrapper, type: RedeemWalletType) -> RedeemSafe3ViewController {
        let service = RedeemSafe3Service()
        let addressService = AddressService(mode: .blockchainType, marketKit: App.shared.marketKit, contactBookManager: nil, blockchainType: .safe)
        let viewModel = RedeemSafe3ViewModel(service: service, addressService: addressService, safe4EvmKitWrapper: safe4EvmKitWrapper, redeemWalletType: type)
        return RedeemSafe3ViewController(account: account, viewModel: viewModel)
    }
    
    enum Tab: Int, CaseIterable {
        case other
        case local
        
        var title: String {
            switch self {
            case .other: return "safe_zone.safe4.redeem.wallet.other".localized
            case .local: return "safe_zone.safe4.redeem.wallet.local".localized
            }
        }
    }
    
    enum RedeemWalletType {
        case local
        case other
    }
}
