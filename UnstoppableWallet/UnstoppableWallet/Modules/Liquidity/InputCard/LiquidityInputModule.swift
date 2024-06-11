import Foundation

class LiquidityInputModule {

    static func cell(service: LiquidityService, tradeService: LiquidityTradeService, switchService: AmountTypeSwitchService) -> LiquidityInputCell {
        let fromCoinCardService = LiquidityFromCoinCardService(service: service, tradeService: tradeService)
        let toCoinCardService = LiquidityToCoinCardService(service: service, tradeService: tradeService)

        let fromFiatService = FiatService(switchService: switchService, currencyManager: App.shared.currencyManager, marketKit: App.shared.marketKit)
        let toFiatService = FiatService(switchService: switchService, currencyManager: App.shared.currencyManager, marketKit: App.shared.marketKit)
        switchService.add(toggleAllowedObservable: fromFiatService.toggleAvailableObservable)
        switchService.add(toggleAllowedObservable: toFiatService.toggleAvailableObservable)

        let fromViewModel = LiquidityCoinCardViewModel(coinCardService: fromCoinCardService, fiatService: fromFiatService)
        let toViewModel = LiquidityCoinCardViewModel(coinCardService: toCoinCardService, fiatService: toFiatService)

        let fromAmountInputViewModel = AmountInputViewModel(
                service: fromCoinCardService,
                fiatService: fromFiatService,
                switchService: switchService,
                decimalParser: AmountDecimalParser()
        )
        let toAmountInputViewModel = AmountInputViewModel(
                service: toCoinCardService,
                fiatService: toFiatService,
                switchService: switchService,
                decimalParser: AmountDecimalParser()
        )

        return LiquidityInputCell(fromViewModel: fromViewModel,
                fromAmountInputViewModel: fromAmountInputViewModel,
                toViewModel: toViewModel,
                toAmountInputViewModel: toAmountInputViewModel
        )
    }
    
    static func cell(service: LiquidityV3Service, tradeService: LiquidityV3TradeService, switchService: AmountTypeSwitchService) -> LiquidityInputCell {
        let fromCoinCardService = LiquidityV3FromCoinCardService(service: service, tradeService: tradeService)
        let toCoinCardService = LiquidityV3ToCoinCardService(service: service, tradeService: tradeService)

        let fromFiatService = FiatService(switchService: switchService, currencyManager: App.shared.currencyManager, marketKit: App.shared.marketKit)
        let toFiatService = FiatService(switchService: switchService, currencyManager: App.shared.currencyManager, marketKit: App.shared.marketKit)
        switchService.add(toggleAllowedObservable: fromFiatService.toggleAvailableObservable)
        switchService.add(toggleAllowedObservable: toFiatService.toggleAvailableObservable)

        let fromViewModel = LiquidityCoinCardViewModel(coinCardService: fromCoinCardService, fiatService: fromFiatService)
        let toViewModel = LiquidityCoinCardViewModel(coinCardService: toCoinCardService, fiatService: toFiatService)

        let fromAmountInputViewModel = AmountInputViewModel(
            service: fromCoinCardService,
            fiatService: fromFiatService,
            switchService: switchService,
            decimalParser: AmountDecimalParser()
        )
        let toAmountInputViewModel = AmountInputViewModel(
            service: toCoinCardService,
            fiatService: toFiatService,
            switchService: switchService,
            decimalParser: AmountDecimalParser()
        )

        return LiquidityInputCell(fromViewModel: fromViewModel,
                             fromAmountInputViewModel: fromAmountInputViewModel,
                             toViewModel: toViewModel,
                             toAmountInputViewModel: toAmountInputViewModel)
    }
}
