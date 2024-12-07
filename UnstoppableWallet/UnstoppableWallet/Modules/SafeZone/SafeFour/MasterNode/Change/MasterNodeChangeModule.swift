import UIKit
import BigInt
import EvmKit

struct MasterNodeChangeModule {
    static func viewController(viewItem: MasterNodeViewModel.ViewItem) -> MasterNodeChangeViewController? {
        guard let evmKitWrapper = App.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            return nil
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else {
            return nil
        }
        
        let service = MasterNodeChangeService(privateKey: privateKey, evmKit: evmKitWrapper.evmKit)
        let viewModel = MasterNodeChangeViewModel(service: service, viewItem: viewItem)
        let viewController = MasterNodeChangeViewController(viewModel: viewModel)
        return viewController
    }
}
