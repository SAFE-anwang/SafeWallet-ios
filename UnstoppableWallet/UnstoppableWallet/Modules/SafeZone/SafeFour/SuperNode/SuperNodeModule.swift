import UIKit
import BigInt

struct SuperNodeModule {

    static func viewController() -> UIViewController? {
        guard let evmKitWrapper = App.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            return nil
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else {
            return nil
        }
        let service = SuperNodeService(evmKit: evmKitWrapper.evmKit)
        let viewModel = SuperNodeViewModel(servie: service)
        return SuperNodeViewController(viewModel: viewModel)
    }

}


