import UIKit
import SwiftUI
import MarketKit
import EvmKit

struct ProposalModule {
    
    static func tabViewModel() -> ProposalTabViewModel? {
        guard let evmKitWrapper = try? Core.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            HudHelper.instance.show(banner: .error(string: "safe_zone.send.openCoin".localized("SAFE")))
            return nil
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else {
            return nil
        }
    
        let viewModel = ProposalTabViewModel(evmKit: evmKitWrapper.evmKit, privateKey: privateKey)
        return viewModel
    }
    
    static func viewModel(type: ProposalType) -> ProposalViewModel {
        let service = ProposalService(type: type)
        let viewModel = ProposalViewModel(service: service)
        return viewModel
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

struct ProposalView: UIViewControllerRepresentable {
    typealias UIViewControllerType = UIViewController
    let viewModel: ProposalViewModel
    
    func makeUIViewController(context _: Context) -> UIViewController {
        // TODO: must provide any VC
        return  ProposalViewController(viewModel: viewModel)
    }

    func updateUIViewController(_: UIViewController, context _: Context) {}
}
