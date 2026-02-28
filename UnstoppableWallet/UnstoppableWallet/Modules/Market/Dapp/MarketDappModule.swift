import Foundation
import SwiftUI
import UIKit

struct MarketDappModule {
//    static func viewModel() -> MarketDappViewModel {
//        let dappProvider = MarketDappProvider(networkManager: Core.shared.networkManager)
//        let service = MarketDappService(provider: dappProvider)
//        let viewModel = MarketDappViewModel(service: service)
//        return viewModel
//    }
}

struct MarketDappListView: UIViewControllerRepresentable {
    typealias UIViewControllerType = UIViewController
    let tab: MarketDappModule.Tab
    func makeUIViewController(context _: Context) -> UIViewController {
        // TODO: must provide any VC
        let dappProvider = MarketDappProvider(networkManager: Core.shared.networkManager)
        let service = MarketDappService(provider: dappProvider, currentTab: tab)
        let viewModel = MarketDappListViewModel(service: service)
        return MarketDappListViewController(viewModel: viewModel, tab: tab)
    }

    func updateUIViewController(_: UIViewController, context _: Context) {}
}

extension MarketDappModule {
    
    enum Tab: Int, CaseIterable, Identifiable {
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
        
        var id: Self {
            self
        }
    }
}

