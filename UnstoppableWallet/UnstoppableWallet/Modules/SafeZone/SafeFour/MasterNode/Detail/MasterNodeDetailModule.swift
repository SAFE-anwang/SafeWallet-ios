import UIKit

struct MasterNodeDetailModule {
    static func viewController(viewItem: MasterNodeViewModel.ViewItem) -> UIViewController? {
        guard let evmKitWrapper = App.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            return nil
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else {
            return nil
        }
         let service = MasterNodeDetailService(privateKey: privateKey, evmKit: evmKitWrapper.evmKit)
        let viewModel = MasterNodeDetailViewModel(nodeViewItem: viewItem, service: service)
        return MasterNodeDetailViewController(viewModel: viewModel)
    }
}
