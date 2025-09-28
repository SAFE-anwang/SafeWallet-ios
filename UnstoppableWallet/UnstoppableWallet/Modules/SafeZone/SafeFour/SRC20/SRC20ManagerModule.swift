import Foundation
import UIKit
import EvmKit
import MarketKit
import ComponentKit

class SRC20ManagerModule {

    static func viewController(nav: UINavigationController) -> UIViewController? {
        guard let evmKitWrapper = App.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            HudHelper.instance.show(banner: .error(string: "safe_zone.send.openCoin".localized("SAFE")))
            return nil
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else {
            return nil
        }
        let provider = SyncSafe4TokensProvider(networkManager: App.shared.networkManager)
        let tokensService = SyncSafe4TokensService(provider: provider, srC20Service: SRC20Service(privateKey: privateKey), evmKit: evmKitWrapper.evmKit, storage: App.shared.safe4CustomTokenStorage, marketKit: App.shared.marketKit)
        let viewModel = SRC20ManagerViewModel(tokensService: tokensService)
        let viewController = SRC20ManagerView(viewModel: viewModel, uiNavController: nav).toViewController()
        return viewController
    }
        
    static func editViewController(token: Safe4CustomTokenRecord, type: SRC20EditType) -> UIViewController? {
        let walletList = App.shared.walletManager.activeWallets
        guard let evmKitWrapper = App.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            return nil
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else {
            return nil
        }
        let service = SRC20Service(token: token, privateKey: privateKey)
        var viewController: UIViewController?
        
        switch type {
        case .edit:
            let viewModel = SRC20EditViewModel(token: token, service: service)
            viewController = SRC20EditView(viewModel: viewModel).toViewController()
            
        case .promotion:
            guard let safeWallet = walletList.filter({$0.coin.uid == safe4CoinUid && $0.token.blockchain.type == .safe4 && $0.token.type == .native}).first else {
                HudHelper.instance.show(banner: .error(string: "safe_zone.send.openCoin".localized("SAFE")))
                return nil
            }
            guard let adapter = App.shared.adapterManager.adapter(for: safeWallet) as? ISendEthereumAdapter else { return nil}
            let viewModel = SRC20PromotionViewModel(token: token, service: service, adapter: adapter)
            viewController = SRC20PromotionView(viewModel: viewModel).toViewController()
            
        case .additional:
            let viewModel = SRC20AdditionalViewModel(token: token, service: service)
            viewController = SRC20AdditionalView(viewModel: viewModel).toViewController()
            
        case .destroy:
            
            let tokenQuery = TokenQuery(blockchainType: .safe4, tokenType: .eip20(address: token.address))
            guard let wsafeWallet = walletList.filter({$0.coin.uid == tokenQuery.customCoinUid && $0.token.blockchain.type == .safe4 }).first else {
                HudHelper.instance.show(banner: .error(string: "safe_zone.send.openCoin".localized(token.symbol)))
                return nil
            }
            guard let adapter = App.shared.adapterManager.adapter(for: wsafeWallet) as? ISendEthereumAdapter else { return nil}
            let viewModel = SRC20DestroyViewModel(token: token, service: service, adapter: adapter)
            viewController = SRC20DestroyView(viewModel: viewModel).toViewController()
        }
        
        return viewController
    }
}

enum SRC20EditType {
    case edit
    case promotion
    case additional
    case destroy
}
