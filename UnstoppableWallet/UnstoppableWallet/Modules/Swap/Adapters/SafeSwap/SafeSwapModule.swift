//import Foundation
//import SafeSwapKit
//import EvmKit
//import StorageKit
//
//class SafeSwapModule {
//    private let tradeService: SafeSwapTradeService
//    private let allowanceService: SwapAllowanceService
//    private let pendingAllowanceService: SwapPendingAllowanceService
//    private let service: SafeSwapService
//
//    init?(dex: SwapModule.Dex, dataSourceState: SwapModule.DataSourceState) {
//        guard let evmKit = App.shared.evmBlockchainManager.evmKitManager(blockchainType: dex.blockchainType).evmKitWrapper?.evmKit else {
//            return nil
//        }
//
//        guard let swapKit = try? SafeSwapKit.Kit.instance(evmKit: evmKit) else {
//            return nil
//        }
//
//        let safeSwapRepository = SafeSwapProvider(swapKit: swapKit)
//
//        tradeService = SafeSwapTradeService(
//                safeSwapProvider: safeSwapRepository,
//                state: dataSourceState,
//                evmKit: evmKit
//        )
//        allowanceService = SwapAllowanceService(
//                spenderAddress: safeSwapRepository.routerAddress,
//                adapterManager: App.shared.adapterManager,
//                evmKit: evmKit
//        )
//        pendingAllowanceService = SwapPendingAllowanceService(
//                spenderAddress: safeSwapRepository.routerAddress,
//                adapterManager: App.shared.adapterManager,
//                allowanceService: allowanceService
//        )
//        service = SafeSwapService(
//                dex: dex,
//                tradeService: tradeService,
//                allowanceService: allowanceService,
//                pendingAllowanceService: pendingAllowanceService,
//                adapterManager: App.shared.adapterManager
//        )
//    }
//
//}
//
//extension SafeSwapModule: ISwapProvider {
//
//    var dataSource: ISwapDataSource {
//        let allowanceViewModel = SwapAllowanceViewModel(errorProvider: service, allowanceService: allowanceService, pendingAllowanceService: pendingAllowanceService)
//        let viewModel = SafeSwapViewModel(
//                service: service,
//                tradeService: tradeService,
//                switchService: AmountTypeSwitchService(localStorage: StorageKit.LocalStorage.default, useLocalStorage: false),
//                allowanceService: allowanceService,
//                pendingAllowanceService: pendingAllowanceService,
//                currencyKit: App.shared.currencyKit,
//                viewItemHelper: SafeSwapViewItemHelper()
//        )
//
//        return SafeSwapDataSource(
//                viewModel: viewModel,
//                allowanceViewModel: allowanceViewModel
//        )
//    }
//
//    var settingsDataSource: ISwapSettingsDataSource? {
//        SafeSwapSettingsModule.dataSource(tradeService: tradeService)
//    }
//
//    var swapState: SwapModule.DataSourceState {
//        let exactIn = tradeService.tradeType == .exactIn
//
//        return SwapModule.DataSourceState(
//                tokenFrom: tradeService.tokenIn,
//                tokenTo: tradeService.tokenOut,
//                amountFrom: tradeService.amountIn,
//                amountTo: tradeService.amountOut,
//                exactFrom: exactIn)
//    }
//
//}
//
//extension SafeSwapModule {
//
//    struct PriceImpactViewItem {
//        let value: String
//        let level: SafeSwapTradeService.PriceImpactLevel
//    }
//
//    struct GuaranteedAmountViewItem {
//        let title: String
//        let value: String?
//    }
//
//    enum SafeSwapWarning: Warning {
//        case highPriceImpact
//    }
//
//    enum TradeError: Error {
//        case wrapUnwrapNotAllowed
//    }
//
//}
//
//extension SafeSwapKit.Kit.TradeError: LocalizedError {
//
//    public var errorDescription: String? {
//        switch self {
//        case .tradeNotFound: return "swap.trade_error.not_found".localized
//        default: return nil
//        }
//    }
//
//}
//
//extension SafeSwapModule.TradeError: LocalizedError {
//
//    public var errorDescription: String? {
//        switch self {
//        case .wrapUnwrapNotAllowed: return "swap.trade_error.wrap_unwrap_not_allowed".localized
//        }
//    }
//
//}

import SafeSwapKit
import EvmKit
import StorageKit

class SafeSwapModule {
    private let tradeService: SafeSwapTradeService
    private let allowanceService: SwapAllowanceService
    private let pendingAllowanceService: SwapPendingAllowanceService
    private let service: SafeSwapService

    init?(dex: SwapModule.Dex, dataSourceState: SwapModule.DataSourceState) {
        guard let evmKit = App.shared.evmBlockchainManager.evmKitManager(blockchainType: dex.blockchainType).evmKitWrapper?.evmKit else {
            return nil
        }

        guard let swapKit = try? SafeSwapKit.Kit.instance(evmKit: evmKit) else {
            return nil
        }

        let safeSwapProvider = SafeSwapProvider(swapKit: swapKit)

        tradeService = SafeSwapTradeService(
                safeSwapProvider: safeSwapProvider,
                state: dataSourceState,
                evmKit: evmKit
        )
        allowanceService = SwapAllowanceService(
                spenderAddress: safeSwapProvider.routerAddress,
                adapterManager: App.shared.adapterManager,
                evmKit: evmKit
        )
        pendingAllowanceService = SwapPendingAllowanceService(
                spenderAddress: safeSwapProvider.routerAddress,
                adapterManager: App.shared.adapterManager,
                allowanceService: allowanceService
        )
        service = SafeSwapService(
                dex: dex,
                evmKit: evmKit,
                tradeService: tradeService,
                allowanceService: allowanceService,
                pendingAllowanceService: pendingAllowanceService,
                adapterManager: App.shared.adapterManager
        )
    }

}

extension SafeSwapModule: ISwapProvider {

    var dataSource: ISwapDataSource {
        let allowanceViewModel = SwapAllowanceViewModel(errorProvider: service, allowanceService: allowanceService, pendingAllowanceService: pendingAllowanceService)
        let viewModel = SafeSwapViewModel(
                service: service,
                tradeService: tradeService,
                switchService: AmountTypeSwitchService(localStorage: StorageKit.LocalStorage.default, useLocalStorage: false),
                allowanceService: allowanceService,
                pendingAllowanceService: pendingAllowanceService,
                currencyKit: App.shared.currencyKit,
                viewItemHelper: SwapViewItemHelper()
        )

        return SafeSwapDataSource(
                viewModel: viewModel,
                allowanceViewModel: allowanceViewModel
        )
    }

    var settingsDataSource: ISwapSettingsDataSource? {
        SafeSwapSettingsModule.dataSource(tradeService: tradeService)
    }

    var swapState: SwapModule.DataSourceState {
        SwapModule.DataSourceState(
                tokenFrom: tradeService.tokenIn,
                tokenTo: tradeService.tokenOut,
                amountFrom: tradeService.amountIn,
                amountTo: tradeService.amountOut,
                exactFrom: true)
    }

}
