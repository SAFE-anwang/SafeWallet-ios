import UIKit
import BigInt
import EvmKit

struct SuperNodeChangeModule {
    static func viewController(viewItem: SuperNodeViewModel.ViewItem) -> SuperNodeChangeViewController? {
        guard let evmKitWrapper = App.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            return nil
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else {
            return nil
        }
        
        let service = SuperNodeChangeService(privateKey: privateKey, evmKit: evmKitWrapper.evmKit)
        let viewModel = SuperNodeChangeViewModel(service: service, viewItem: viewItem)
        let viewController = SuperNodeChangeViewController(viewModel: viewModel)
        return viewController
    }
}
