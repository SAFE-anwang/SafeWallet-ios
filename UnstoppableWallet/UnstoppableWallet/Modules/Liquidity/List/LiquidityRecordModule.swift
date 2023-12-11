import Foundation
import UIKit
import MarketKit
import EvmKit
import BigInt
import ThemeKit
import UniswapKit

class LiquidityRecordModule {
    static func viewController() -> UIViewController? {
        
        guard let evmKitWrapper = App.shared.evmBlockchainManager.evmKitManager(blockchainType: .binanceSmartChain).evmKitWrapper else {
            return nil
        }
        
        guard let swapKit = try? UniswapKit.Kit.instance(evmKit: evmKitWrapper.evmKit) else {
            return nil
        }                
        let service = LiquidityRecordService(
            marketKit: App.shared.marketKit,
            walletManager: App.shared.walletManager,
            adapterManager: App.shared.adapterManager,
            evmKitWrapper: evmKitWrapper,
            swapKit: swapKit
        )
        let viewModel =  LiquidityRecordViewModel(service: service)
        let viewController = LiquidityRecordViewController(viewModel: viewModel)

        return viewController//ThemeNavigationController(rootViewController: viewController)
    }

}



