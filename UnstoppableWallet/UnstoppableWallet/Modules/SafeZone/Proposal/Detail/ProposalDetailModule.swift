import UIKit
import SwiftUI

struct ProposalDetailModule {
    static func viewModel(viewItem: ProposalViewModel.ViewItem) -> ProposalDetailViewModel? {
        guard let evmKitWrapper = try? Core.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            return nil
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else {
            return nil
        }
        let service = ProposalDetailService(privateKey: privateKey, evmKit: evmKitWrapper.evmKit)
        let viewModel = ProposalDetailViewModel(infoItem: viewItem, servie: service)
        return viewModel
    }
}
struct ProposalDetailView: UIViewControllerRepresentable {
    typealias UIViewControllerType = UIViewController
    let viewModel: ProposalDetailViewModel
    
    func makeUIViewController(context _: Context) -> UIViewController {
        // TODO: must provide any VC
        return ThemeNavigationController(rootViewController: ProposalDetailViewController(viewModel: viewModel))
    }

    func updateUIViewController(_: UIViewController, context _: Context) {}
}
