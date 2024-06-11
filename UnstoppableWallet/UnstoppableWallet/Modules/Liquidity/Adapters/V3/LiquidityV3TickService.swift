import BigInt
import EvmKit
import Foundation
import HsToolKit
import MarketKit
import RxRelay
import RxSwift
import UniswapKit

class LiquidityV3TickService {
    
    private let swapKit: UniswapKit.KitV3
    private let evmKit: EvmKit.Kit
    
    private let disposeBag = DisposeBag()
    
    private var tickLower: BigInt? {
        didSet {
            if tickLower != oldValue {
                setTickRange()
            }
        }
    }
    
    private var tickUpper: BigInt? {
        didSet {
            if tickUpper != oldValue {
                setTickRange()
            }
        }
    }
    
    private(set) var liquidityTickType: UniswapKit.KitV3.LiquidityTickType = .range(lower: nil, upper: nil) {
        didSet {
            if liquidityTickType != oldValue {
                tickRangeRelay.accept(liquidityTickType)
            }
        }
    }
    
//    var viewIsEditing = false

    private var tickRangeRelay = PublishRelay<UniswapKit.KitV3.LiquidityTickType>()
    private var tickPairRelay = PublishRelay<String?>()
    
    private let scheduler = SerialDispatchQueueScheduler(qos: .userInitiated, internalSerialQueueName: "\(AppConfig.label).tick_service")
    
    init(swapKit: UniswapKit.KitV3, evmKit: EvmKit.Kit) {
        self.swapKit = swapKit
        self.evmKit = evmKit
    }
}

extension LiquidityV3TickService {
    
    enum PriceType {
        case lowest
        case highest
        case current
    }
    
    enum TickServiceError: Error {
        case encodeSqrtRatioError
    }
}

extension LiquidityV3TickService {
    
    var tickRangeObservable: Observable<UniswapKit.KitV3.LiquidityTickType> {
        tickRangeRelay.asObservable()
    }
    
    var tickPairObservable: Observable<String?> {
        tickPairRelay.asObservable()
    }
    
    func syncTick(bestTrade: TradeDataV3?) {
        tickLower = bestTrade?.tickInfo?.tickLower
        tickUpper = bestTrade?.tickInfo?.tickUpper
    }

    func priceToTick(type: PriceType, price: Decimal, tokenIn: MarketKit.Token, tokenOut: MarketKit.Token) throws {
        let token0 = try uniswapToken(token: tokenIn)
        let token1 = try uniswapToken(token: tokenOut)

        if token0.sortsBefore(token: token1) {
            guard let sqrtPriceX96 = swapKit.encodeSqrtRatioX96(price: price, tokenA: token0, tokenB: token1) else{
                throw TickServiceError.encodeSqrtRatioError
            }
            let tick = price == 0 ? swapKit.minTick : try swapKit.getTickAtSqrtRatio(sqrtRatioX96: sqrtPriceX96)
            switch type {
            case .lowest:
                tickLower = max(tick, swapKit.minTick)
            case .highest:
                tickUpper = min(tick, swapKit.maxTick)
            case .current: ()
            }

        }else {
            guard let sqrtPriceX96 = swapKit.encodeSqrtRatioX96(price: price, tokenA: token0, tokenB: token1) else{
                throw TickServiceError.encodeSqrtRatioError
            }
            let tick = price == 0 ? swapKit.maxTick : try swapKit.getTickAtSqrtRatio(sqrtRatioX96: sqrtPriceX96)
            switch type {
            case .lowest:
                tickUpper = min(tick, swapKit.maxTick)
            case .highest:
                tickLower = max(tick, swapKit.minTick)

            case .current: ()
            }
            
        }
    }
    
    func onTapMinusTick(type: PriceType, tickSpacing: BigUInt?, tokenIn: MarketKit.Token, tokenOut: MarketKit.Token) throws {
        guard let tickSpacing else { return }
        guard let lower = tickLower else { return }
        guard let upper = tickUpper else { return }
        let token0 = try uniswapToken(token: tokenIn)
        let token1 = try uniswapToken(token: tokenOut)
        


        if token0.sortsBefore(token: token1) {
            switch type {
            case .lowest:
                tickLower = lower - BigInt(tickSpacing)
            case .highest:
                let tick = upper - BigInt(tickSpacing)
                guard tick > lower else { return }
                tickUpper = tick
            case .current: ()
            }
        }else {
            switch type {
            case .lowest:
                tickUpper = upper + BigInt(tickSpacing)
            case .highest:
                let tick = lower + BigInt(tickSpacing)
                guard tick < upper else { return }
                tickLower = tick
            case .current: ()
            }
        }
    }
    
    func onTapPlusTick(type: PriceType, tickSpacing: BigUInt?, tokenIn: MarketKit.Token, tokenOut: MarketKit.Token) throws {
        guard let tickSpacing else { return }
        guard let lower = tickLower else { return }
        guard let upper = tickUpper else { return }
        let token0 = try uniswapToken(token: tokenIn)
        let token1 = try uniswapToken(token: tokenOut)
        
        if token0.sortsBefore(token: token1) {
            switch type {
            case .lowest:
                let tick = lower + BigInt(tickSpacing)
                guard tick < upper else { return }
                tickLower = tick
            case .highest:
                tickUpper = upper + BigInt(tickSpacing)
            case .current: ()
            }
        }else {
            switch type {
            case .lowest:
                let tick = upper - BigInt(tickSpacing)
                guard tick > lower else { return }
                tickUpper = tick
            case .highest:
                tickLower = lower - BigInt(tickSpacing)
            case .current: ()
            }
        }
    }
    
    
    func setPair(text: String?) {
        tickPairRelay.accept(text)
    }
    
    func setTickRange(multi: Decimal) {
        liquidityTickType = .multi(value: multi)
    }
    
    func setTickFullRange() {
        liquidityTickType = .full
    }
    
    private func setTickRange() {
        if tickLower == swapKit.minTick, tickUpper == swapKit.maxTick {
            liquidityTickType = .full
        }else {
            liquidityTickType = .range(lower: tickLower, upper: tickUpper)
        }
    }
    
    private func uniswapToken(token: MarketKit.Token) throws -> UniswapKit.Token {
        switch token.type {
        case .native: return try swapKit.etherToken(chain: evmKit.chain)
        case let .eip20(address): return try swapKit.token(contractAddress: EvmKit.Address(hex: address), decimals: token.decimals)
        default: throw LiquidityV3Provider.TokenError.unsupportedToken
        }
    }
}

private extension UniswapKit.Token {
    func sortsBefore(token: UniswapKit.Token) -> Bool {
        address.raw.hs.hexString.lowercased() < token.address.raw.hs.hexString.lowercased()
    }
}
