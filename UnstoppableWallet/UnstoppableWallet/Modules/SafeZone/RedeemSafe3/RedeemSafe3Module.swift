import UIKit
import SwiftUI
import EvmKit
import MarketKit

struct RedeemSafe3Module {
    static func tabViewModel() -> RedeemSafe3TabViewModel? {
        let walletList = Core.shared.walletManager.activeWallets
        var safe4Wallet: Wallet?
        
        for wallet in walletList {
            if wallet.coin.uid == safe4CoinUid {
                if wallet.token.blockchain.type == .safe4 {
                    safe4Wallet = wallet
                }
            }
        }
        
        guard let safe4Wallet else {
            HudHelper.instance.show(banner: .error(string: "safe_zone.send.openCoin".localized("SAFE")))
            return nil
        }
        guard let account = Core.shared.accountManager.activeAccount else { return nil }
        
        guard let state = WalletAdapterService(account: account, adapterManager: Core.shared.adapterManager).state(wallet: safe4Wallet), state == .synced else {
            HudHelper.instance.show(banner: .error(string: "SAFE" + "balance.syncing".localized))
            return nil
        }
        
        guard let safe4EvmKitWrapper = try? Core.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            return nil
        }

        let  viewModel = RedeemSafe3TabViewModel(account: account, safe4EvmKitWrapper: safe4EvmKitWrapper)
        return viewModel
    }
    
//    static func viewController() -> UIViewController? {
//        let walletList = Core.shared.walletManager.activeWallets
//        var safe4Wallet: Wallet?
//        
//        for wallet in walletList {
//            if wallet.coin.uid == safe4CoinUid {
//                if wallet.token.blockchain.type == .safe4 {
//                    safe4Wallet = wallet
//                }
//            }
//        }
//        
//        guard let safe4Wallet else {
//            HudHelper.instance.show(banner: .error(string: "safe_zone.send.openCoin".localized("SAFE")))
//            return nil
//        }
//        guard let account = Core.shared.accountManager.activeAccount else { return nil }
//        
//        guard let state = WalletAdapterService(account: account, adapterManager: Core.shared.adapterManager).state(wallet: safe4Wallet), state == .synced else {
//            HudHelper.instance.show(banner: .error(string: "SAFE" + "balance.syncing".localized))
//            return nil
//        }
//        
//        guard let safe4EvmKitWrapper = try? Core.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
//            return nil
//        }
//
//        let  viewModel = RedeemSafe3TabViewModel()
//        return RedeemSafe3TabViewController(account: account, viewModel: viewModel, safe4EvmKitWrapper: safe4EvmKitWrapper)
//    }
    
//    static func subViewController(account: Account, safe4EvmKitWrapper: EvmKitWrapper, type: RedeemWalletType) -> RedeemSafe3ViewController {
//        let service = RedeemSafe3Service()
//        let addressService = AddressService(mode: .blockchainType, marketKit: Core.shared.marketKit, contactBookManager: nil, blockchainType: .safe)
//        let viewModel = RedeemSafe3ViewModel(service: service, addressService: addressService, safe4EvmKitWrapper: safe4EvmKitWrapper, redeemWalletType: type)
//        return RedeemSafe3ViewController(account: account, viewModel: viewModel)
//    }
    
    static func viewModel(account: Account, safe4EvmKitWrapper: EvmKitWrapper, type: RedeemWalletType) -> RedeemSafe3ViewModel {
        let service = RedeemSafe3Service()
        let addressService = AddressService(mode: .blockchainType, marketKit: Core.shared.marketKit, contactBookManager: nil, blockchainType: .safe)
        let viewModel = RedeemSafe3ViewModel(service: service, addressService: addressService, safe4EvmKitWrapper: safe4EvmKitWrapper, redeemWalletType: type)
        return viewModel
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

struct RedeemSafe3View: UIViewControllerRepresentable {
    typealias UIViewControllerType = UIViewController
    let viewModel: RedeemSafe3ViewModel
    let account: Account
    
    func makeUIViewController(context _: Context) -> UIViewController {
        // TODO: must provide any VC
        return RedeemSafe3ViewController(account: account, viewModel: viewModel)
    }

    func updateUIViewController(_: UIViewController, context _: Context) {}
}
