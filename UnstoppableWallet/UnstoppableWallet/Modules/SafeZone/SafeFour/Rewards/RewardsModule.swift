import UIKit
import HsToolKit

struct RewardsModule {
    static func viewController() -> UIViewController? {
        guard let evmKitWrapper = App.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            return nil
        }
        let address = evmKitWrapper.evmKit.address.hex
        let provider = Safe4Provider(networkManager: NetworkManager(logger: Logger(minLogLevel: .debug)))
        let service = RewardsService(provider: provider, address: address)
        let viewModel = RewardsViewModel(service: service)
        return RewardsViewController(viewModel: viewModel)
    }
}
