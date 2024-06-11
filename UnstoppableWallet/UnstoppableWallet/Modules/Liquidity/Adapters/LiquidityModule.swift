import Foundation
import UniswapKit
import EvmKit

class LiquidityModule {
    private let tradeService: LiquidityTradeService
    private let service: LiquidityService

    private let allowanceService: LiquidityAllowanceService
    private let pendingAllowanceService: LiquidityPendingAllowanceService

    init?(dex: LiquidityMainModule.Dex, dataSourceState: LiquidityMainModule.DataSourceState) {

        guard let evmKit = App.shared.evmBlockchainManager.evmKitManager(blockchainType: dex.blockchainType).evmKitWrapper?.evmKit else {
            return nil
        }

        guard let swapKit = try? UniswapKit.Kit.instance(),
              let rpcSource = App.shared.evmSyncSourceManager.httpSyncSource(blockchainType: dex.blockchainType)?.rpcSource
        else {
            return nil
        }

        let liquidityRepository = LiquidityProvider(swapKit: swapKit, evmKit: evmKit, rpcSource: rpcSource)

        tradeService = LiquidityTradeService(
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

        service = LiquidityService(
                dex: dex,
                tradeService: tradeService,
                allowanceService: allowanceService,
                pendingAllowanceService: pendingAllowanceService,
                adapterManager: App.shared.adapterManager
        )
    }

}

extension LiquidityModule: ILiquidityProvider {

    var dataSource: ILiquidityDataSource {
        let allowanceViewModel = LiquidityAllowanceViewModel(errorProvider: service, allowanceService: allowanceService, pendingAllowanceService: pendingAllowanceService)
        let viewModel = LiquidityViewModel(
                service: service,
                tradeService: tradeService,
                switchService: AmountTypeSwitchService(userDefaultsStorage: App.shared.userDefaultsStorage, useLocalStorage: false),
                allowanceService: allowanceService,
                pendingAllowanceService: pendingAllowanceService,
                currencyManager: App.shared.currencyManager,
                viewItemHelper: LiquidityViewItemHelper()
        )

        return LiquidityDataSource(
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

extension LiquidityModule {

    struct PriceImpactViewItem {
        let value: String
        let level: LiquidityTradeService.PriceImpactLevel
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

extension LiquidityModule.TradeError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case .wrapUnwrapNotAllowed: return "swap.trade_error.wrap_unwrap_not_allowed".localized
        }
    }

}
