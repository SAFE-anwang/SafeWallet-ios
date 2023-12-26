import Foundation
import UniswapKit
import EvmKit
import StorageKit

class PancakeLiquidityModule {
    private let tradeService: PancakeLiquidityTradeService
    private let service: PancakeLiquidityService

    private let allowanceService: LiquidityAllowanceService
    private let pendingAllowanceService: LiquidityPendingAllowanceService

    init?(dex: LiquidityMainModule.Dex, dataSourceState: LiquidityMainModule.DataSourceState) {
        guard let evmKit = App.shared.evmBlockchainManager.evmKitManager(blockchainType: dex.blockchainType).evmKitWrapper?.evmKit else {
            return nil
        }

        guard let swapKit = try? UniswapKit.Kit.instance(evmKit: evmKit) else {
            return nil
        }

        let liquidityRepository = PancakeLiquidityProvider(swapKit: swapKit)

        tradeService = PancakeLiquidityTradeService(
                liquidityProvider: liquidityRepository,
                state: dataSourceState,
                evmKit: evmKit
        )
        
        allowanceService = LiquidityAllowanceService(
                spenderAddress: liquidityRepository.routerAddress,
                adapterManager: App.shared.adapterManager,
                evmKit: evmKit
        )
        
        pendingAllowanceService = LiquidityPendingAllowanceService(
                spenderAddress: liquidityRepository.routerAddress,
                adapterManager: App.shared.adapterManager,
                allowanceService: allowanceService
        )

        service = PancakeLiquidityService(
                dex: dex,
                tradeService: tradeService,
                allowanceService: allowanceService,
                pendingAllowanceService: pendingAllowanceService,
                adapterManager: App.shared.adapterManager
        )
    }

}

extension PancakeLiquidityModule: ILiquidityProvider {

    var dataSource: ILiquidityDataSource {
        let allowanceViewModel = LiquidityAllowanceViewModel(errorProvider: service, allowanceService: allowanceService, pendingAllowanceService: pendingAllowanceService)
        let viewModel = PancakeLiquidityViewModel(
                service: service,
                tradeService: tradeService,
                switchService: AmountTypeSwitchService(localStorage: StorageKit.LocalStorage.default, useLocalStorage: false),
                allowanceService: allowanceService,
                pendingAllowanceService: pendingAllowanceService,
                currencyKit: App.shared.currencyKit,
                viewItemHelper: LiquidityViewItemHelper()
        )

        return PancakeLiquidityDataSource(
                viewModel: viewModel,
                allowanceViewModel: allowanceViewModel
        )
    }

    var settingsDataSource: ISwapSettingsDataSource? {
        UniswapSettingsModule.dataSource(settingProvider: tradeService, showDeadline: true)
    }

    var swapState: LiquidityMainModule.DataSourceState {
        let exactIn = tradeService.tradeType == .exactIn

        return LiquidityMainModule.DataSourceState(
                tokenFrom: tradeService.tokenIn,
                tokenTo: tradeService.tokenOut,
                amountFrom: tradeService.amountIn,
                amountTo: tradeService.amountOut,
                exactFrom: exactIn)
    }

}

extension PancakeLiquidityModule {

    struct PriceImpactViewItem {
        let value: String
        let level: PancakeLiquidityTradeService.PriceImpactLevel
    }

    struct GuaranteedAmountViewItem {
        let title: String
        let value: String?
    }

    enum LiquidityWarning: Warning {
        case highPriceImpact
        case forbiddenPriceImpact
    }

    enum LiquidityError: Error {
        case forbiddenPriceImpact(provider: String)
    }

    enum TradeError: Error {
        case wrapUnwrapNotAllowed
    }

}

extension PancakeLiquidityModule.TradeError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case .wrapUnwrapNotAllowed: return "swap.trade_error.wrap_unwrap_not_allowed".localized
        }
    }

}
