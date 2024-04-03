import Foundation
import UIKit
import ThemeKit
import MarketKit
import ComponentKit
import SectionsTableView
import Kingfisher

struct MarketDappModule {
    static func viewController() -> MarketDappViewController {
        let dappProvider = MarketDappProvider(networkManager: App.shared.networkManager)
        let service = MarketDappService(provider: dappProvider)
        let viewModel = MarketDappViewModel(service: service)
        return MarketDappViewController(viewModel: viewModel)
    }
    
    static func subViewController(tab: MarketDappModule.Tab) -> MarketDappListViewController {
        let dappProvider = MarketDappProvider(networkManager: App.shared.networkManager)
        let service = MarketDappService(provider: dappProvider)
        let viewModel = MarketDappViewModel(service: service)
        return MarketDappListViewController(viewModel: viewModel, urlManager: UrlManager(inApp: true), tab: tab)
    }
}


extension MarketDappModule {
    
    enum Tab: Int, CaseIterable {
        case ALL
        case ETH
        case BSC
        case SAFE
        
        var title: String {
            switch self {
            case .ALL: return "transactions.types.all".localized
            case .ETH: return "ETH"
            case .BSC: return "BSC"
            case .SAFE: return "SAFE"
            }
        }
    }
}


