import UIKit

struct SecuritySettingsModule {

    static func viewController() -> UIViewController {
        let service = SecuritySettingsService(pinKit: App.shared.pinKit)
        let viewModel = SecuritySettingsViewModel(service: service)
        
        let blockchainSettingsService = BlockchainSettingsService(
                btcBlockchainManager: App.shared.btcBlockchainManager,
                evmBlockchainManager: App.shared.evmBlockchainManager,
                evmSyncSourceManager: App.shared.evmSyncSourceManager
        )
        let blockchainSettingsViewModel = BlockchainSettingsViewModel(service: blockchainSettingsService)
        
        return SecuritySettingsViewController(viewModel: viewModel, blockchainSettingsViewModel: blockchainSettingsViewModel)
    }

}
