import UIKit
import ThemeKit
import EvmKit
import SafeSwapKit

//struct SafeSwapConfirmationModule {
//
//    static func viewController(sendData: SendEvmData, dex: SwapModule.Dex) -> UIViewController? {
//        guard let evmKitWrapper =  App.shared.evmBlockchainManager.evmKitManager(blockchainType: dex.blockchainType).evmKitWrapper else {
//            return nil
//        }
//
//        guard let coinServiceFactory = EvmCoinServiceFactory(
//                blockchainType: dex.blockchainType,
//                marketKit: App.shared.marketKit,
//                currencyKit: App.shared.currencyKit,
//                evmBlockchainManager: App.shared.evmBlockchainManager,
//                coinManager: App.shared.coinManager
//        ) else {
//            return nil
//        }
//
//        let gasPriceService = EvmFeeModule.gasPriceService(evmKit: evmKitWrapper.evmKit)
//        let gasDataService = EvmCommonGasDataService.instance(evmKit: evmKitWrapper.evmKit, blockchainType: evmKitWrapper.blockchainType, gasLimitSurchargePercent: 20)
//        let feeService = EvmFeeService(evmKit: evmKitWrapper.evmKit, gasPriceService: gasPriceService, gasDataService: gasDataService, coinService: <#CoinService#>, transactionData: sendData.transactionData)
//        let service = SendEvmTransactionService(sendData: sendData, evmKitWrapper: evmKitWrapper, settingsService: feeService, evmLabelManager: App.shared.evmLabelManager)
//
//        let transactionViewModel = SendEvmTransactionViewModel(service: service, coinServiceFactory: coinServiceFactory, cautionsFactory: SendEvmCautionsFactory(), evmLabelManager: App.shared.evmLabelManager, contactLabelService: <#ContactLabelService#>)
//        let feeViewModel = EvmFeeViewModel(service: feeService, gasPriceService: gasPriceService, coinService: coinServiceFactory.baseCoinService)
//
//        return SwapConfirmationViewController(transactionViewModel: transactionViewModel, feeViewModel: feeViewModel)
//    }
//
//    static func viewController(parameters: SafeSwapParameters, dex: SwapModule.Dex) -> UIViewController? {
//        guard let evmKitWrapper =  App.shared.evmBlockchainManager.evmKitManager(blockchainType: dex.blockchainType).evmKitWrapper else {
//            return nil
//        }
//
//        guard let swapKit = try? SafeSwapKit.Kit.instance(evmKit: evmKitWrapper.evmKit) else {
//            return nil
//        }
//
//        let safeSwapProvider = SafeSwapProvider(swapKit: swapKit)
//
//        guard let coinServiceFactory = EvmCoinServiceFactory(
//                blockchainType: dex.blockchainType,
//                marketKit: App.shared.marketKit,
//                currencyKit: App.shared.currencyKit,
//                evmBlockchainManager: App.shared.evmBlockchainManager,
//                coinManager: App.shared.coinManager
//        ) else {
//            return nil
//        }
//
//        let gasPriceService = EvmFeeModule.gasPriceService(evmKit: evmKitWrapper.evmKit)
//        let feeService = SafeSwapFeeService(evmKit: evmKitWrapper.evmKit,  provider: safeSwapProvider, gasPriceService: gasPriceService, parameters: parameters)
//        let service = SafeSwapSendEvmTransactionService(evmKitWrapper: evmKitWrapper, transactionFeeService: feeService)
//
//        let transactionViewModel = SendEvmTransactionViewModel(service: service, coinServiceFactory: coinServiceFactory, cautionsFactory: SendEvmCautionsFactory(), evmLabelManager: App.shared.evmLabelManager)
//        let feeViewModel = EvmFeeViewModel(service: feeService, gasPriceService: gasPriceService, coinService: coinServiceFactory.baseCoinService)
//
//        return SwapConfirmationViewController(transactionViewModel: transactionViewModel, feeViewModel: feeViewModel)
//    }
//
//}

struct SafeSwapConfirmationModule {

    static func viewController(sendData: SendEvmData, dex: SwapModule.Dex) -> UIViewController? {
        guard let evmKitWrapper =  App.shared.evmBlockchainManager.evmKitManager(blockchainType: dex.blockchainType).evmKitWrapper else {
            return nil
        }

        guard let coinServiceFactory = EvmCoinServiceFactory(
                blockchainType: dex.blockchainType,
                marketKit: App.shared.marketKit,
                currencyKit: App.shared.currencyKit,
                evmBlockchainManager: App.shared.evmBlockchainManager,
                coinManager: App.shared.coinManager
        ) else {
            return nil
        }

        guard let (settingsService, settingsViewModel) = EvmSendSettingsModule.instance(
                evmKit: evmKitWrapper.evmKit, blockchainType: evmKitWrapper.blockchainType, sendData: sendData, coinServiceFactory: coinServiceFactory,
                gasLimitSurchargePercent: 20
        ) else {
            return nil
        }

        let service = SendEvmTransactionService(sendData: sendData, evmKitWrapper: evmKitWrapper, settingsService: settingsService, evmLabelManager: App.shared.evmLabelManager)
        let contactLabelService = ContactLabelService(contactManager: App.shared.contactManager, blockchainType: evmKitWrapper.blockchainType)
        let viewModel = SendEvmTransactionViewModel(service: service, coinServiceFactory: coinServiceFactory, cautionsFactory: SendEvmCautionsFactory(), evmLabelManager: App.shared.evmLabelManager, contactLabelService: contactLabelService)

        return SwapConfirmationViewController(transactionViewModel: viewModel, settingsViewModel: settingsViewModel)
    }

    static func viewController(parameters: SafeSwapParameters, dex: SwapModule.Dex) -> UIViewController? {
        guard let evmKitWrapper =  App.shared.evmBlockchainManager.evmKitManager(blockchainType: dex.blockchainType).evmKitWrapper else {
            return nil
        }

        let evmKit = evmKitWrapper.evmKit
        guard let swapKit = try? SafeSwapKit.Kit.instance(evmKit: evmKit) else {
            return nil
        }

        let SafeSwapProvider = SafeSwapProvider(swapKit: swapKit)

        guard let coinServiceFactory = EvmCoinServiceFactory(
                blockchainType: dex.blockchainType,
                marketKit: App.shared.marketKit,
                currencyKit: App.shared.currencyKit,
                evmBlockchainManager: App.shared.evmBlockchainManager,
                coinManager: App.shared.coinManager
        ) else {
            return nil
        }

        let gasPriceService = EvmFeeModule.gasPriceService(evmKit: evmKit)
        let coinService = coinServiceFactory.baseCoinService
        let feeViewItemFactory = FeeViewItemFactory(scale: coinService.token.blockchainType.feePriceScale)
        let nonceService = NonceService(evmKit: evmKit, replacingNonce: nil)
        let feeService = SafeSwapFeeService(evmKit: evmKit,  provider: SafeSwapProvider, gasPriceService: gasPriceService, coinService: coinServiceFactory.baseCoinService, parameters: parameters)
        let settingsService = EvmSendSettingsService(feeService: feeService, nonceService: nonceService)

        let cautionsFactory = SendEvmCautionsFactory()
        let nonceViewModel = NonceViewModel(service: nonceService)

        let settingsViewModel: EvmSendSettingsViewModel
        switch gasPriceService {
        case let legacyService as LegacyGasPriceService:
            let feeViewModel = LegacyEvmFeeViewModel(gasPriceService: legacyService, feeService: feeService, coinService: coinService, feeViewItemFactory: feeViewItemFactory)
            settingsViewModel = EvmSendSettingsViewModel(service: settingsService, feeViewModel: feeViewModel, nonceViewModel: nonceViewModel, cautionsFactory: cautionsFactory)

        case let eip1559Service as Eip1559GasPriceService:
            let feeViewModel = Eip1559EvmFeeViewModel(gasPriceService: eip1559Service, feeService: feeService, coinService: coinService, feeViewItemFactory: feeViewItemFactory)
            settingsViewModel = EvmSendSettingsViewModel(service: settingsService, feeViewModel: feeViewModel, nonceViewModel: nonceViewModel, cautionsFactory: cautionsFactory)

        default: return nil
        }

        let transactionSettings = SafeSwapSendEvmTransactionService(evmKitWrapper: evmKitWrapper, safeSwapFeeService: feeService, settingsService: settingsService)
        let contactLabelService = ContactLabelService(contactManager: App.shared.contactManager, blockchainType: evmKitWrapper.blockchainType)
        let transactionViewModel = SendEvmTransactionViewModel(service: transactionSettings, coinServiceFactory: coinServiceFactory, cautionsFactory: SendEvmCautionsFactory(), evmLabelManager: App.shared.evmLabelManager, contactLabelService: contactLabelService)

        return SwapConfirmationViewController(transactionViewModel: transactionViewModel, settingsViewModel: settingsViewModel)
    }
}
