import UIKit
import EvmKit
import OneInchKit

struct LiquidityConfirmationModule {

    static func viewController(sendData: SendEvmData, dex: LiquidityMainModule.Dex) -> UIViewController? {
        guard let evmKitWrapper = try? Core.shared.evmBlockchainManager.evmKitManager(blockchainType: dex.blockchainType).evmKitWrapper else {
            return nil
        }

        guard let coinServiceFactory = EvmCoinServiceFactory(
                blockchainType: dex.blockchainType,
                marketKit: Core.shared.marketKit,
                currencyManager: Core.shared.currencyManager,
                coinManager: Core.shared.coinManager
        ) else {
            return nil
        }
        
        let gasPriceService = EvmFeeModule.gasPriceService(evmKit: evmKitWrapper.evmKit)

        let predefinedGasLimit: Int?
        switch dex.provider {
        case .uniswapV3, .pancakeV3:
            predefinedGasLimit = 650000
        case .uniswap, .pancake, .safeSwap:
            predefinedGasLimit = 500000
        default:
            predefinedGasLimit = nil
        }
        
        let coinService = coinServiceFactory.baseCoinService
        let feeViewItemFactory = FeeViewItemFactory(scale: coinService.token.blockchainType.feePriceScale)
        let feeService = LiquidityFeeService(evmKit: evmKitWrapper.evmKit, gasPriceService: gasPriceService, coinService: coinService, transactionData: sendData.transactionData, predefinedGasLimit: predefinedGasLimit)
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
        
        guard let chainToken = Core.shared.evmBlockchainManager.baseToken(blockchainType: dex.blockchainType) else {
            return nil
        }

        let service = AddLiquidityTransactionService(sendData: sendData, evmKitWrapper: evmKitWrapper, settingsService: settingService, evmLabelManager: Core.shared.evmLabelManager)
        let contactLabelService = ContactLabelService(contactManager: Core.shared.contactManager, blockchainType: evmKitWrapper.blockchainType)
        let viewModel = AddLiquidityTransactionViewModel(service: service, coinServiceFactory: coinServiceFactory, cautionsFactory: SendEvmCautionsFactory(), evmLabelManager: Core.shared.evmLabelManager, contactLabelService: contactLabelService, marketKit: Core.shared.marketKit, currencyManager: Core.shared.currencyManager, chainToken: chainToken)

        return  LiquidityConfirmationViewController(transactionViewModel: viewModel, settingsViewModel: settingsViewModel)
    }
}

