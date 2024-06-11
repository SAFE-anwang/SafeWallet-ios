import Foundation
import RxSwift
import RxCocoa
import UniswapKit
import MarketKit
import BigInt

class LiquidityTickInputCardViewModel {

    private let disposeBag = DisposeBag()
    private var readOnlyRelay = BehaviorRelay<Bool>(value: false)
    private var isEstimatedRelay = BehaviorRelay<Bool>(value: false)
    private var priceRelay = BehaviorRelay<String?>(value: nil)
    private var pairRelay = BehaviorRelay<String?>(value: nil)
    
    private let decimalParser = AmountDecimalParser()
        
    private(set) var price: Decimal?
    private var tickSpacing: BigUInt?
        
    private let type: LiquidityV3TickService.PriceType
    private let tickService: LiquidityV3TickService
    private let tradeService: LiquidityV3TradeService
    
    private let scheduler = SerialDispatchQueueScheduler(qos: .userInitiated, internalSerialQueueName: "\(AppConfig.label).liquidity_tick_service")
    
    init(type: LiquidityV3TickService.PriceType, tickService: LiquidityV3TickService, tradeService: LiquidityV3TradeService) {
        self.type = type
        self.tickService = tickService
        self.tradeService = tradeService
        
        if case .current = type {
            readOnlyRelay.accept(true)
        } else {
            readOnlyRelay.accept(false)
        }

        subscribe(scheduler, disposeBag, tradeService.stateObservable) { [weak self] state in
            self?.onUpdateTrade(state: state)
        }
        
        subscribe(scheduler, disposeBag, tickService.tickPairObservable) { [weak self] text in
            self?.pairRelay.accept(text)
        }
        
    }
    private func onUpdateTrade(state: LiquidityV3TradeService.State) {
        switch state {
        case .loading, .notReady(errors: _):
            tickSpacing = nil
            if tradeService.tokenIn == nil || tradeService.tokenOut == nil {
                priceRelay.accept(nil)
            }
        case let .ready(trade):
            tickSpacing = trade.tradeData.tickInfo?.tickSpacing
            updatePrice(trade: trade)
        }
    }
    
    private func updatePrice(trade: LiquidityV3TradeService.Trade) {
        guard let tickInfo = trade.tradeData.tickInfo else { return priceRelay.accept(nil)}
        var price: String? = nil
        switch type {
        case .lowest:
            price = tickInfo.isMinTick ? "0" : tickInfo.tickLowerPrice?.description
            
        case .highest:
            price = tickInfo.isMaxTick ? "∞" : tickInfo.tickUpperPrice?.description
        case .current:
            price = trade.tradeData.tickInfo?.tickcurrentPrice?.description
        }
        priceRelay.accept(price)
    }
}

extension LiquidityTickInputCardViewModel {

    var readOnlyDriver: Driver<Bool> {
        readOnlyRelay.asDriver()
    }

    var priceDriver: Driver<String?> {
        priceRelay.asDriver()
    }
    
    var pairDriver: Driver<String?> {
        pairRelay.asDriver()
    }

    func onChange(price: String?) {
        let amount = decimalParser.parseAnyDecimal(from: price) ?? 0
        guard let tokenIn = tradeService.tokenIn, let tokenOut = tradeService.tokenOut else { return }
        do {
            try tickService.priceToTick(type: type, price: amount, tokenIn: tokenIn, tokenOut: tokenOut)
        }catch {}
    }
    
    func setTickRange(type: RangeType) {
        switch type {
        case .full:
            tickService.setTickFullRange()
        case let .range(value):
            tickService.setTickRange(multi: value)
        }
    }
    
    func onTapMinusTick() {
        guard let tokenIn = tradeService.tokenIn, let tokenOut = tradeService.tokenOut else { return }
        do {
            try tickService.onTapMinusTick(type: type, tickSpacing: tickSpacing, tokenIn: tokenIn, tokenOut: tokenOut)
        }catch {}
        
    }
    
    func onTapPlusTick() {
        guard let tokenIn = tradeService.tokenIn, let tokenOut = tradeService.tokenOut else { return }
        do {
            try tickService.onTapPlusTick(type: type, tickSpacing: tickSpacing, tokenIn: tokenIn, tokenOut: tokenOut)
        }catch {}
        
    }
    
}


