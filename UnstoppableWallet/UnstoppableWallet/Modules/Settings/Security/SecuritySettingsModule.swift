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
        let fallbackBlockViewModel = FallbackBlockViewModel(walletManager: App.shared.walletManager, accountManager: App.shared.accountManager, adapterManager: App.shared.adapterManager)
        
        return SecuritySettingsViewController(viewModel: viewModel, blockchainSettingsViewModel: blockchainSettingsViewModel, fallbackBlockViewModel: fallbackBlockViewModel)
    }
}
