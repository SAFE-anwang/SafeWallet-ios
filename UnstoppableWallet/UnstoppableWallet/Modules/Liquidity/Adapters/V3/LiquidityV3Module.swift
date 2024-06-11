import EvmKit
import Foundation
import UniswapKit

class LiquidityV3Module {
    private let tickService: LiquidityV3TickService
    private let tradeService: LiquidityV3TradeService
    private let allowanceService: LiquidityAllowanceService
    private let pendingAllowanceService: LiquidityPendingAllowanceService
    private let service: LiquidityV3Service

    init?(dex: LiquidityMainModule.Dex, dataSourceState: LiquidityMainModule.DataSourceState) {
        guard let evmKit = App.shared.evmBlockchainManager.evmKitManager(blockchainType: dex.blockchainType).evmKitWrapper?.evmKit else {
            return nil
        }

        guard let swapKit = try? UniswapKit.KitV3.instance(dexType: dex.provider.dexType),
              let rpcSource = App.shared.evmSyncSourceManager.httpSyncSource(blockchainType: dex.blockchainType)?.rpcSource
        else {
            return nil
        }

        let uniswapRepository = LiquidityV3Provider(swapKit: swapKit, evmKit: evmKit, rpcSource: rpcSource)
        
        tickService = LiquidityV3TickService(
            swapKit: swapKit,
            evmKit: evmKit
        )
        tradeService = LiquidityV3TradeService(
            uniswapProvider: uniswapRepository,
            state: dataSourceState,
            evmKit: evmKit,
            tickService: tickService
        )
        allowanceService = LiquidityAllowanceService(
            spenderAddress: uniswapRepository.nonfungiblePositionAddress,
            adapterManager: App.shared.adapterManager,
            evmKit: evmKit
        )
        pendingAllowanceService = LiquidityPendingAllowanceService(
            spenderAddress: uniswapRepository.nonfungiblePositionAddress,
            adapterManager: App.shared.adapterManager,
            allowanceService: allowanceService
        )
        service = LiquidityV3Service(
            dex: dex,
            tradeService: tradeService,
            allowanceService: allowanceService,
            pendingAllowanceService: pendingAllowanceService,
            adapterManager: App.shared.adapterManager
        )
    }
}

extension LiquidityV3Module: ILiquidityProvider {
    var dataSource: ILiquidityDataSource {
        let allowanceViewModel = LiquidityAllowanceViewModel(errorProvider: service, allowanceService: allowanceService, pendingAllowanceService: pendingAllowanceService)
        let viewModel = LiquidityV3ViewModel(
            service: service,
            tradeService: tradeService,
            switchService: AmountTypeSwitchService(userDefaultsStorage: App.shared.userDefaultsStorage, useLocalStorage: false),
            allowanceService: allowanceService,
            pendingAllowanceService: pendingAllowanceService,
            currencyManager: App.shared.currencyManager,
            viewItemHelper: LiquidityViewItemHelper()
        )
        
        let lowerTickViewModel = LiquidityTickInputCardViewModel(type: .lowest, tickService: tickService, tradeService: tradeService)
        let upperTickViewModel = LiquidityTickInputCardViewModel(type: .highest, tickService: tickService, tradeService: tradeService)
        let currentTickViewModel = LiquidityTickInputCardViewModel(type: .current, tickService: tickService, tradeService: tradeService)

        return LiquidityV3DataSource(viewModel: viewModel,
                                     allowanceViewModel: allowanceViewModel,
                                     lowerTickViewModel: lowerTickViewModel,
                                     upperTickViewModel: upperTickViewModel,
                                     currentTickViewModel: currentTickViewModel
        )
    }

    var settingsDataSource: ISwapSettingsDataSource? {
        UniswapSettingsModule.dataSource(settingProvider: tradeService, showDeadline: false)
    }

    var swapState: LiquidityMainModule.DataSourceState {
        let exactIn = tradeService.tradeType == .exactIn

        return LiquidityMainModule.DataSourceState(
            tokenFrom: tradeService.tokenIn,
            tokenTo: tradeService.tokenOut,
            amountFrom: tradeService.amountIn,
            amountTo: tradeService.amountOut,
            exactFrom: exactIn
        )
    }
}

extension LiquidityV3Module {
    struct PriceImpactViewItem {
        let value: String
        let level: UniswapTradeService.PriceImpactLevel
    }

    struct GuaranteedAmountViewItem {
        let title: String
        let value: String?
    }

    enum UniswapWarning: Warning {
        case highPriceImpact
    }

    enum TradeError: Error {
        case wrapUnwrapNotAllowed
    }
}

