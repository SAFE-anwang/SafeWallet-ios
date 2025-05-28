import Foundation
import UIKit
import MarketKit
import EvmKit
import BigInt
import ThemeKit
import UniswapKit

class LiquidityRecordModule {
    
    static func viewController() -> UIViewController? {
                      
        let viewModel = LiquidityRecordTabViewModel()
        let viewController = LiquidityRecordTabViewController(viewModel: viewModel)

        return viewController
    }
    
    static func subViewController(dexType: UniswapKit.DexType, blockchainType: BlockchainType) -> LiquidityRecordViewController {

        let v2Service = LiquidityRecordService(
            marketKit: App.shared.marketKit,
            walletManager: App.shared.walletManager,
            adapterManager: App.shared.adapterManager,
            blockchainType: blockchainType
        )
        
        let v3Service = LiquidityV3RecordService(
            dexType: dexType,
            marketKit: App.shared.marketKit,
            walletManager: App.shared.walletManager,
            adapterManager: App.shared.adapterManager,
            blockchainType: blockchainType
        )
        
        let viewModel =  LiquidityRecordViewModel(service: v2Service)
        let v3ViewModel =  LiquidityV3RecordViewModel(service: v3Service)
        let viewController = LiquidityRecordViewController(viewModel: viewModel, v3ViewModel: v3ViewModel)

        return viewController
    }
    
    static func removeConfirmViewController(viewModel: LiquidityRecordViewModel, recordItem: LiquidityRecordViewModel.RecordItem) -> UIViewController? {
        let viewController = LiquidityRemoveConfirmViewController(viewModel: viewModel, recordItem: recordItem)
        return viewController
    }
    
    enum Tab: Int, CaseIterable {
        case safe
        case bsc
        case eth
        
        var title: String {
            switch self {
            case .safe: return "SAFE"
            case .bsc: return "BSC".localized
            case .eth: return "ETH".localized
            }
        }
    }
}



