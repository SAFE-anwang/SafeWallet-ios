import UIKit
import MarketKit
import ComponentKit

struct ProposalModule {

    static func viewController() -> UIViewController? {
        guard let evmKitWrapper = App.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            HudHelper.instance.show(banner: .error(string: "safe_zone.send.openCoin".localized("SAFE4")))
            return nil
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else {
            return nil
        }
    
        let viewModel = ProposalTabViewModel(evmKit: evmKitWrapper.evmKit)
        let viewController = ProposalTabViewController(viewModel: viewModel, privateKey: privateKey, evmKit: evmKitWrapper.evmKit)
        return viewController
    }
    
    static func subViewController(type: ProposalType) -> ProposalViewController {
        let service = ProposalService(type: type)
        let viewModel = ProposalViewModel(service: service)
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
        case Mine(address: String)
    }
}
