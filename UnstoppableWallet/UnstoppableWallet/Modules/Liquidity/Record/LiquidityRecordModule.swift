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
    
    static func subViewController(blockchainType: BlockchainType) -> LiquidityRecordViewController {
        


        let service = LiquidityRecordService(
            marketKit: App.shared.marketKit,
            walletManager: App.shared.walletManager,
            adapterManager: App.shared.adapterManager,
            blockchainType: blockchainType
        )
        let viewModel =  LiquidityRecordViewModel(service: service)
        let viewController = LiquidityRecordViewController(viewModel: viewModel)

        return viewController
    }
    
    static func removeConfirmViewController(viewModel: LiquidityRecordViewModel, recordItem: LiquidityRecordViewModel.RecordItem) -> UIViewController? {
        let viewController = LiquidityRemoveConfirmViewController(viewModel: viewModel, recordItem: recordItem)
        return viewController
    }
    

    enum Tab: Int, CaseIterable {
        case bsc
        case eth
        
        var title: String {
            switch self {
            case .bsc: return "BSC".localized
            case .eth: return "ETH".localized
            }
        }
    }
}



