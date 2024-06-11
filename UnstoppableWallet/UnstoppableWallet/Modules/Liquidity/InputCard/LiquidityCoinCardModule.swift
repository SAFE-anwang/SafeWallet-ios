
import Foundation
import UniswapKit
import RxSwift
import MarketKit

protocol ILiquidityCoinCardService: AnyObject {
    var dex: LiquidityMainModule.Dex { get }
    var readOnly: Bool { get }
    var isEstimated: Bool { get }
    var token: MarketKit.Token? { get }
    var balance: Decimal? { get }
    var amount: Decimal { get }

    var readOnlyObservable: Observable<Bool> { get }
    var isEstimatedObservable: Observable<Bool> { get }
    var tokenObservable: Observable<MarketKit.Token?> { get }
    var balanceObservable: Observable<Decimal?> { get }
    var errorObservable: Observable<Error?> { get }
    var amountObservable: Observable<Decimal> { get }
    var isLoading: Observable<Bool> { get }

    func onChange(token: MarketKit.Token)
}

extension ILiquidityCoinCardService {

    var readOnly: Bool {
        false
    }

    var readOnlyObservable: Observable<Bool> {
        Observable.just(false)
    }

}

class LiquidityFromCoinCardService: ILiquidityCoinCardService, IAmountInputService {
    private let service: LiquidityService
    private let tradeService: LiquidityTradeService

    init(service: LiquidityService, tradeService: LiquidityTradeService) {
        self.service = service
        self.tradeService = tradeService
    }

    var dex: LiquidityMainModule.Dex { service.dex }
    var isEstimated: Bool { tradeService.tradeType != .exactIn }
    var amount: Decimal { tradeService.amountIn }
    var token: MarketKit.Token? { tradeService.tokenIn }
    var balance: Decimal? { service.balanceIn }

    var isEstimatedObservable: Observable<Bool> { tradeService.tradeTypeObservable.map { $0 != .exactIn } }
    var amountObservable: Observable<Decimal> { tradeService.amountInObservable }
    var tokenObservable: Observable<MarketKit.Token?> { tradeService.tokenInObservable }
    var balanceObservable: Observable<Decimal?> { service.balanceInObservable }
    var errorObservable: Observable<Error?> {
        service.errorsObservable.map {
            $0.first(where: { .insufficientBalanceIn == $0 as? SwapModule.SwapError })
        }
    }
    var isLoading: Observable<Bool> {
        tradeService.stateObservable.map { state in
            switch state {
            case .loading: return true
            default: return false
            }
        }
    }

    func onChange(amount: Decimal) {
        tradeService.set(amountIn: amount)
    }

    func onChange(token: MarketKit.Token) {
        tradeService.set(tokenIn: token)
    }

}

class LiquidityToCoinCardService: ILiquidityCoinCardService, IAmountInputService {
    private let service: LiquidityService
    private let tradeService: LiquidityTradeService

    init(service: LiquidityService, tradeService: LiquidityTradeService) {
        self.service = service
        self.tradeService = tradeService
    }

    var dex: LiquidityMainModule.Dex { service.dex }
    var isEstimated: Bool { tradeService.tradeType != .exactOut }
    var amount: Decimal { tradeService.amountOut }
    var token: MarketKit.Token? { tradeService.tokenOut }
    var balance: Decimal? { service.balanceOut }

    var isEstimatedObservable: Observable<Bool> { tradeService.tradeTypeObservable.map { $0 != .exactOut } }
    var amountObservable: Observable<Decimal> { tradeService.amountOutObservable }
    var tokenObservable: Observable<MarketKit.Token?> { tradeService.tokenOutObservable }
    var balanceObservable: Observable<Decimal?> { service.balanceOutObservable }
    var errorObservable: Observable<Error?> {
        Observable<Error?>.just(nil)
    }
    var isLoading: Observable<Bool> {
        tradeService.stateObservable.map { state in
            switch state {
            case .loading: return true
            default: return false
            }
        }
    }

    var amountWarningObservable: Observable<AmountInputViewModel.AmountWarning?> {
        tradeService.stateObservable.map { state in
            guard case .ready(let trade) = state,
                  let impactLevel = trade.impactLevel,
                  case .forbidden = impactLevel,
                  let priceImpact = trade.tradeData.priceImpact else {
                return nil
            }

            return .highPriceImpact(priceImpact: priceImpact)
        }
    }

    func onChange(amount: Decimal) {
        tradeService.set(amountOut: amount)
    }

    func onChange(token: MarketKit.Token) {
        tradeService.set(tokenOut: token)
    }

}

class LiquidityV3FromCoinCardService: ILiquidityCoinCardService, IAmountInputService {
    private let service: LiquidityV3Service
    private let tradeService: LiquidityV3TradeService

    init(service: LiquidityV3Service, tradeService: LiquidityV3TradeService) {
        self.service = service
        self.tradeService = tradeService
    }

    var dex: LiquidityMainModule.Dex { service.dex }
    var isEstimated: Bool { tradeService.tradeType != .exactIn }
    var amount: Decimal { tradeService.amountIn }
    var token: MarketKit.Token? { tradeService.tokenIn }
    var balance: Decimal? { service.balanceIn }

    var isEstimatedObservable: Observable<Bool> { tradeService.tradeTypeObservable.map { $0 != .exactIn } }
    var amountObservable: Observable<Decimal> { tradeService.amountInObservable }
    var tokenObservable: Observable<MarketKit.Token?> { tradeService.tokenInObservable }
    var balanceObservable: Observable<Decimal?> { service.balanceInObservable }
    var errorObservable: Observable<Error?> {
        service.errorsObservable.map {
            $0.first(where: { $0 as? SwapModule.SwapError == .insufficientBalanceIn })
        }
    }

    var isLoading: Observable<Bool> {
        tradeService.stateObservable.map { state in
            switch state {
            case .loading: return true
            default: return false
            }
        }
    }

    func onChange(amount: Decimal) {
        tradeService.set(amountIn: amount)
    }

    func onChange(token: MarketKit.Token) {
        tradeService.set(tokenIn: token)
    }
}

class LiquidityV3ToCoinCardService: ILiquidityCoinCardService, IAmountInputService {
    
    private let service: LiquidityV3Service
    private let tradeService: LiquidityV3TradeService

    init(service: LiquidityV3Service, tradeService: LiquidityV3TradeService) {
        self.service = service
        self.tradeService = tradeService
    }

    var dex: LiquidityMainModule.Dex { service.dex }
    var readOnly: Bool { true }
    var isEstimated: Bool { tradeService.tradeType != .exactOut }
    var amount: Decimal { tradeService.amountOut }
    var token: MarketKit.Token? { tradeService.tokenOut }
    var balance: Decimal? { service.balanceOut }

    var isEstimatedObservable: Observable<Bool> { tradeService.tradeTypeObservable.map { $0 != .exactOut } }
    var amountObservable: Observable<Decimal> { tradeService.amountOutObservable }
    var tokenObservable: Observable<MarketKit.Token?> { tradeService.tokenOutObservable }
    var balanceObservable: Observable<Decimal?> { service.balanceOutObservable }
    var errorObservable: Observable<Error?> {
        Observable<Error?>.just(nil)
    }

    var isLoading: Observable<Bool> {
        tradeService.stateObservable.map { state in
            switch state {
            case .loading: return true
            default: return false
            }
        }
    }

    var amountWarningObservable: Observable<AmountInputViewModel.AmountWarning?> {
        tradeService.stateObservable.map { state in
            guard case let .ready(trade) = state,
                  let impactLevel = trade.impactLevel,
                  case .forbidden = impactLevel,
                  let priceImpact = trade.tradeData.priceImpact
            else {
                return nil
            }

            return .highPriceImpact(priceImpact: priceImpact)
        }
    }

    func onChange(amount: Decimal) {
        tradeService.set(amountOut: amount)
    }

    func onChange(token: MarketKit.Token) {
        tradeService.set(tokenOut: token)
    }
}
