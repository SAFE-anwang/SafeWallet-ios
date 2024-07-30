import UIKit
import MarketKit

struct ProposalModule {

    static func viewController() -> UIViewController? {
        guard let evmKit = App.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            return nil
        }
        guard let privateKey = evmKit.signer?.privateKey else {
            return nil
        }
        
//        let query = TokenQuery(blockchainType: .safe4, tokenType: .native)
//        guard let token = try? App.shared.marketKit.token(query: query) else {
//            return nil
//        }

        let viewModel = ProposalTabViewModel()
        let viewController = ProposalTabViewController(viewModel: viewModel, privateKey: privateKey) 
        return viewController
    }
    
    static func subViewController(type: ProposalType) -> ProposalViewController {
        let service = ProposalService(type: type)
        let viewModel = ProposalViewModel(servie: service)
        return ProposalViewController(viewModel: viewModel)
    }
    
    enum Tab: Int, CaseIterable {
        case all
        case mine
        
        var title: String {
            switch self {
            case .all: return "safe_zone.safe4.proposal.all".localized
            case .mine: return "safe_zone.safe4.proposal.mine".localized
            }
        }
    }
    
    enum ProposalType {
        case All
        case Mine(privateKey: Data)
    }
}
