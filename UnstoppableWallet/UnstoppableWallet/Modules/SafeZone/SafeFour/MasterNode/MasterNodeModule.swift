import UIKit

struct MasterNodeModule {
    static func viewController() -> UIViewController? {
        guard let evmKitWrapper = App.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            return nil
        }
        let service = MasterNodeService(evmKit: evmKitWrapper.evmKit)
        let viewModel = MasterNodeViewModel(servie: service)
        return MasterNodeViewController(viewModel: viewModel)
    }
}
