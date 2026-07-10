import UIKit
import HsToolKit
import SwiftUI

struct RewardsModule {

    static func viewModel() -> RewardsViewModel? {
        guard let evmKitWrapper = try? Core.shared.evmBlockchainManager.evmKitManager(blockchainType: .safe4).evmKitWrapper else {
            return nil
        }
        guard let privateKey = evmKitWrapper.signer?.privateKey else { return nil }
        let address = evmKitWrapper.evmKit.address.hex
        let provider = Safe4Provider(networkManager: NetworkManager(logger: Logger(minLogLevel: .debug)))
        let service = RewardsService(provider: provider, address: address, privateKey: privateKey, evmKit: evmKitWrapper.evmKit)
        let viewModel = RewardsViewModel(service: service)
        return viewModel
    }

}
