import UIKit

struct SuperNodeDetailModule {
    static func viewController(nodeType: Safe4NodeType, viewItem: SuperNodeViewModel.ViewItem) -> UIViewController? {
        guard let evmKitWrapper = App.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            return nil
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else {
            return nil
        }
        let viewModel = SuperNodeDetailViewModel(nodeType: nodeType, nodeViewItem: viewItem, service: SuperNodeDetailService(privateKey: privateKey, evmKit: evmKitWrapper.evmKit))
        return SuperNodeDetailViewController(viewModel: viewModel)
    }
}
