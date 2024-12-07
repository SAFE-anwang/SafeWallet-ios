import UIKit

struct SuperNodeDetailModule {
    static func viewController(viewItem: SuperNodeViewModel.ViewItem, viewType: SuperNodeDetailViewModel.ViewType) -> SuperNodeDetailViewController? {
        guard let evmKitWrapper = App.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            return nil
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else {
            return nil
        }
        let viewModel = SuperNodeDetailViewModel(nodeViewItem: viewItem, service: SuperNodeDetailService(privateKey: privateKey, evmKit: evmKitWrapper.evmKit))
        return SuperNodeDetailViewController(viewModel: viewModel, viewType: viewType)
    }
}

