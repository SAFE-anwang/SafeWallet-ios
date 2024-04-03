import UIKit
import ThemeKit
import EvmKit
import OneInchKit

struct LiquidityConfirmationModule {

    static func viewController(sendData: SendEvmData, dex: LiquidityMainModule.Dex) -> UIViewController? {
        guard let evmKitWrapper =  App.shared.evmBlockchainManager.evmKitManager(blockchainType: dex.blockchainType).evmKitWrapper else {
            return nil
        }

        guard let coinServiceFactory = EvmCoinServiceFactory(
                blockchainType: dex.blockchainType,
                marketKit: App.shared.marketKit,
                currencyManager: App.shared.currencyManager,
                coinManager: App.shared.coinManager
        ) else {
            return nil
        }
        
        let gasPriceService = EvmFeeModule.gasPriceService(evmKit: evmKitWrapper.evmKit)

        let gasDataService = EvmCommonGasDataService.instance(
                evmKit: evmKitWrapper.evmKit,
                blockchainType: evmKitWrapper.blockchainType,
                predefinedGasLimit: 500000,
                gasLimitType: .contract
        )
        
        let coinService = coinServiceFactory.baseCoinService
        let feeViewItemFactory = FeeViewItemFactory(scale: coinService.token.blockchainType.feePriceScale)
        let feeService = LiquidityFeeService(evmKit: evmKitWrapper.evmKit, gasPriceService: gasPriceService, gasDataService: gasDataService, coinService: coinService, transactionData: sendData.transactionData)
        let nonceService = NonceService(evmKit: evmKitWrapper.evmKit, replacingNonce: nil)
        let settingService = EvmSendSettingsService(feeService: feeService, nonceService: nonceService)
        
        let cautionsFactory = SendEvmCautionsFactory()
        let nonceViewModel = NonceViewModel(service: nonceService)
        
        let settingsViewModel: EvmSendSettingsViewModel
        switch gasPriceService {
        case let legacyService as LegacyGasPriceService:
            let feeViewModel = LegacyEvmFeeViewModel(gasPriceService: legacyService, feeService: feeService, coinService: coinService, feeViewItemFactory: feeViewItemFactory)
            settingsViewModel = EvmSendSettingsViewModel(service: settingService, feeViewModel: feeViewModel, nonceViewModel: nonceViewModel, cautionsFactory: cautionsFactory)
            
        case let eip1559Service as Eip1559GasPriceService:
            let feeViewModel = Eip1559EvmFeeViewModel(gasPriceService: eip1559Service, feeService: feeService, coinService: coinService, feeViewItemFactory: feeViewItemFactory)
            settingsViewModel = EvmSendSettingsViewModel(service: settingService, feeViewModel: feeViewModel, nonceViewModel: nonceViewModel, cautionsFactory: cautionsFactory)
            
        default: return nil
        }
        
        guard let chainToken = App.shared.evmBlockchainManager.baseToken(blockchainType: dex.blockchainType) else {
            return nil
        }

        let service = AddLiquidityTransactionService(sendData: sendData, evmKitWrapper: evmKitWrapper, settingsService: settingService, evmLabelManager: App.shared.evmLabelManager)
        let contactLabelService = ContactLabelService(contactManager: App.shared.contactManager, blockchainType: evmKitWrapper.blockchainType)
        let viewModel = AddLiquidityTransactionViewModel(service: service, coinServiceFactory: coinServiceFactory, cautionsFactory: SendEvmCautionsFactory(), evmLabelManager: App.shared.evmLabelManager, contactLabelService: contactLabelService, marketKit: App.shared.marketKit, currencyManager: App.shared.currencyManager, chainToken: chainToken)

        return  LiquidityConfirmationViewController(transactionViewModel: viewModel, settingsViewModel: settingsViewModel)
    }

}

