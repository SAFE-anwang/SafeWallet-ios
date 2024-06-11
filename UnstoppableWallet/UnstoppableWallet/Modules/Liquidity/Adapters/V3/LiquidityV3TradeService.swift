import Combine
import EvmKit
import Foundation
import HsExtensions
import MarketKit
import RxRelay
import RxSwift
import UniswapKit
import BigInt

class LiquidityV3TradeService: ISwapSettingProvider {
    private static let timerFramePerSecond: Int = 30

    private var disposeBag = DisposeBag()

    private var refreshTimerTask: AnyTask?
    private var refreshTimerCancellable: Cancellable?
    private var refreshTimerDisposeBag = DisposeBag()

    private var cancellables = Set<AnyCancellable>()
    private var tasks = Set<AnyTask>()

    private static let normalPriceImpact: Decimal = 1
    private static let warningPriceImpact: Decimal = 5
    private static let forbiddenPriceImpact: Decimal = 20

    private let uniswapProvider: LiquidityV3Provider
    private let tickService: LiquidityV3TickService

    let syncInterval: TimeInterval

    private var bestTrade: TradeDataV3?

    private(set) var tokenIn: MarketKit.Token? {
        didSet {
            if tokenIn != oldValue {
                tokenInRelay.accept(tokenIn)
            }
        }
    }

    private(set) var tokenOut: MarketKit.Token? {
        didSet {
            if tokenOut != oldValue {
                tokenOutRelay.accept(tokenOut)
            }
        }
    }

    private(set) var amountIn: Decimal = 0 {
        didSet {
            if amountIn != oldValue {
                amountInRelay.accept(amountIn)
            }
        }
    }

    private(set) var amountOut: Decimal = 0 {
        didSet {
            if amountOut != oldValue {
                amountOutRelay.accept(amountOut)
            }
        }
    }

    private(set) var tradeType: TradeType = .exactIn {
        didSet {
            if tradeType != oldValue {
                tradeTypeRelay.accept(tradeType)
            }
        }
    }
    
    private var tradeTypeRelay = PublishRelay<TradeType>()
    private var tokenInRelay = PublishRelay<MarketKit.Token?>()
    private var tokenOutRelay = PublishRelay<MarketKit.Token?>()

    private var amountInRelay = PublishRelay<Decimal>()
    private var amountOutRelay = PublishRelay<Decimal>()

    private let stateRelay = PublishRelay<State>()
    private(set) var state: State = .notReady(errors: []) {
        didSet {
            stateRelay.accept(state)
        }
    }

    private let countdownTimerRelay = PublishRelay<Float>()

    private let settingsRelay = PublishRelay<UniswapSettings>()
    var settings = UniswapSettings() {
        didSet {
            settingsRelay.accept(settings)
            _ = syncTradeData()
        }
    }
    
    private let scheduler = SerialDispatchQueueScheduler(qos: .userInitiated, internalSerialQueueName: "\(AppConfig.label).LiquidityV3Trade_service")
    
    init(uniswapProvider: LiquidityV3Provider, state: LiquidityMainModule.DataSourceState, evmKit: EvmKit.Kit, tickService: LiquidityV3TickService) {
        self.uniswapProvider = uniswapProvider
        self.tickService = tickService

        syncInterval = evmKit.chain.syncInterval

        tokenIn = state.tokenFrom
        tokenOut = state.tokenTo
        if state.exactFrom {
            amountIn = state.amountFrom ?? 0
        } else {
            amountOut = state.amountTo ?? 0
        }

        evmKit.lastBlockHeightPublisher
            .sink { [weak self] _ in
                self?.syncTradeData()
            }
            .store(in: &cancellables)
        

        subscribe(scheduler, disposeBag, tickService.tickRangeObservable) { [weak self] type in
            self?.syncTradeData()
        }
        
        syncTradeData()
    }

    private func syncTimer() {
        refreshTimerTask?.cancel()
        let tickerCount = Int(syncInterval) * Self.timerFramePerSecond

        refreshTimerTask = Task { [weak self] in
            for i in 0 ... tickerCount {
                try await Task.sleep(nanoseconds: 1_000_000_000 / UInt64(Self.timerFramePerSecond))
                self?.countdownTimerRelay.accept(Float(i) / Float(tickerCount))
            }

            self?.syncTradeData()
        }.erased()
    }

    @discardableResult private func syncTradeData() -> Bool {
        guard let tokenIn,
              let tokenOut
        else {
            state = .notReady(errors: [])
            return false
        }
    
        tasks = Set()
        syncTimer()

        state = .loading

        let amount = amountIn

        guard amount > 0 else {
            state = .notReady(errors: [])
            return false
        }
        
        let tickType = tickService.liquidityTickType
        if case let .range(tickLower, tickUpper) = tickType {
            if let lower = tickLower, let upper = tickUpper {
                guard upper > lower else {
                    state = .notReady(errors: [UniswapModule.TradeError.lessTickRangeError])//.notReady(errors: [UniswapModule.TradeError.tickRangeError])
                    return false
                }
//                if let tickCurrent = bestTrade?.tickInfo?.tickCurrent {
//                    guard tickCurrent > lower else {
//                        state = .notReady(errors: [UniswapModule.TradeError.lessTickRangeError])
//                        return false
//                    }
//                    
//                    guard upper > tickCurrent else {
//                        state = .notReady(errors: [UniswapModule.TradeError.greaterTickRangeError])
//                        return false
//                    }
//                }
            }
        }

        Task { [weak self, uniswapProvider] in
            do {
                let tradeOptions = TradeOptions()
                let bestTrade = try await uniswapProvider.bestTrade(tokenIn: tokenIn, tokenOut: tokenOut, amount: amount, tradeOptions: tradeOptions, tickType: tickType)
                self?.handle(tradeData: bestTrade)
            } catch {
                var convertedError = error

                if case UniswapKit.KitV3.TradeError.tradeNotFound = error {
                    let wethAddressString = uniswapProvider.wethAddress.hex

                    if case .native = tokenIn.type, case let .eip20(address) = tokenOut.type, address == wethAddressString {
                        convertedError = UniswapModule.TradeError.wrapUnwrapNotAllowed
                    }

                    if case .native = tokenOut.type, case let .eip20(address) = tokenIn.type, address == wethAddressString {
                        convertedError = UniswapModule.TradeError.wrapUnwrapNotAllowed
                    }
                }

                self?.state = .notReady(errors: [convertedError])
            }
        }.store(in: &tasks)

        return true
    }

    private func handle(tradeData: TradeDataV3) {
        bestTrade = tradeData

        switch tradeData.type {
        case .exactIn:
            amountOut = tradeData.amountOut ?? 0
        case .exactOut:
            amountIn = tradeData.amountIn ?? 0
        }

        let trade = Trade(tradeData: tradeData)
        tickService.syncTick(bestTrade: tradeData)
        state = .ready(trade: trade)

    }
}

protocol ILiquidityV3TradeService {
    var stateObservable: Observable<UniswapTradeService.State> { get }
}

extension LiquidityV3TradeService {
    var stateObservable: Observable<State> {
        stateRelay.asObservable()
    }

    var countdownTimerObservable: Observable<Float> {
        countdownTimerRelay.asObservable()
    }

    var tradeTypeObservable: Observable<TradeType> {
        tradeTypeRelay.asObservable()
    }

    var tokenInObservable: Observable<MarketKit.Token?> {
        tokenInRelay.asObservable()
    }

    var tokenOutObservable: Observable<MarketKit.Token?> {
        tokenOutRelay.asObservable()
    }

    var amountInObservable: Observable<Decimal> {
        amountInRelay.asObservable()
    }

    var amountOutObservable: Observable<Decimal> {
        amountOutRelay.asObservable()
    }

    var settingsObservable: Observable<UniswapSettings> {
        settingsRelay.asObservable()
    }

    func transactionData(tradeData: TradeDataV3) async throws -> TransactionData? {
        return try await uniswapProvider.transactionData(tradeData: tradeData, tradeOptions: settings.tradeOptions)
    }

    func set(tokenIn: MarketKit.Token?) {
        guard self.tokenIn != tokenIn else {
            return
        }

        self.tokenIn = tokenIn
        amountIn = 0

        if tradeType == .exactIn {
            amountOut = 0
        }

        if tokenOut == tokenIn {
            tokenOut = nil
            amountOut = 0
        }

        bestTrade = nil
        syncTradeData()
        syncTickPair()
    }

    func set(tokenOut: MarketKit.Token?) {
        guard self.tokenOut != tokenOut else {
            return
        }

        self.tokenOut = tokenOut
        amountOut = 0

        if tradeType == .exactOut {
            amountIn = 0
        }

        if tokenIn == tokenOut {
            tokenIn = nil
            amountIn = 0
        }

        bestTrade = nil
        syncTradeData()
        syncTickPair()
    }

    func set(amountIn: Decimal) {
        guard self.amountIn != amountIn else {
            return
        }

        tradeType = .exactIn

        self.amountIn = amountIn

        if !syncTradeData() {
            amountOut = 0
        }
    }

    func set(amountOut: Decimal) {
        guard self.amountOut != amountOut else {
            return
        }

        tradeType = .exactOut

        self.amountOut = amountOut

        if !syncTradeData() {
            amountIn = 0
        }
    }

    func switchCoins() {
        let swapToken = tokenOut
        tokenOut = tokenIn

        set(tokenIn: swapToken)
        syncTickPair()
    }
    
    func syncTickPair() {
        guard let tokenIn, let tokenOut else {
            tickService.setPair(text: nil)
            return
        }
        let text = "\(tokenOut.coin.code)\("liquidity.tick.price.per".localized)\(tokenIn.coin.code)"
        tickService.setPair(text: text)
    }
}

extension LiquidityV3TradeService {
    enum State {
        case loading
        case ready(trade: Trade)
        case notReady(errors: [Error])
    }

    struct Trade {
        let tradeData: TradeDataV3
        let impactLevel: LiquidityTradeService.PriceImpactLevel?
        
        init(tradeData: TradeDataV3) {
            self.tradeData = tradeData
            impactLevel = .negligible
//            impactLevel = tradeData.priceImpact.map { priceImpact in
//                return .negligible
//                if priceImpact < LiquidityV3TradeService.normalPriceImpact {
//                    return .negligible
//                }
//                if priceImpact < LiquidityV3TradeService.warningPriceImpact {
//                    return .normal
//                }
//                if priceImpact < LiquidityV3TradeService.forbiddenPriceImpact {
//                    return .warning
//                }
//                return .forbidden
//            }
        }
    }
}
