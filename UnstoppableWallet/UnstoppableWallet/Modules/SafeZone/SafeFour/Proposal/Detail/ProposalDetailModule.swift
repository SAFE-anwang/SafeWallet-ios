import UIKit

struct ProposalDetailModule {
    static func viewController(viewItem: ProposalViewModel.ViewItem) -> ProposalDetailViewController? {
        guard let evmKitWrapper = App.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            return nil
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else {
            return nil
        }
        let service = ProposalDetailService(privateKey: privateKey, evmKit: evmKitWrapper.evmKit)
        let viewModel = ProposalDetailViewModel(infoItem: viewItem, servie: service)
        return ProposalDetailViewController(viewModel: viewModel)
    }
}
