import EvmKit
import BigInt
import Foundation
import MarketKit
import UniswapKit

class BaseUniswapV3LiquidityAddProvider: BaseUniswapLiquidityAddProvider {
    private let kit: UniswapKit.KitV3
    private let rpcSource: RpcSource
    var tickType: KitV3.LiquidityTickType = .full

    init(kit: UniswapKit.KitV3, storage: MultiSwapSettingStorage, rpcSource: RpcSource) {
        self.kit = kit
        self.rpcSource = rpcSource
        super.init(storage: storage)
    }

    override func spenderAddress(chain: Chain) throws -> EvmKit.Address {
        kit.nonfungiblePositionAddress(chain: chain)
    }

    override func kitToken(chain: Chain, token: MarketKit.Token) throws -> UniswapKit.Token {
        switch token.type {
        case .native: return try kit.etherToken(chain: chain)
        case let .eip20(address): return try kit.token(contractAddress: EvmKit.Address(hex: address), decimals: token.decimals)
        default: throw SwapError.invalidToken
        }
    }

    override func trade(rpcSource: RpcSource, chain: Chain, token0: UniswapKit.Token, token1: UniswapKit.Token, amountIn: Decimal, tradeOptions: TradeOptions) async throws -> UniswapLiquidityAddQuote.Trade {
        let preferredTrade = try await quoteTrade(
            rpcSource: rpcSource,
            chain: chain,
            tokenIn: token0,
            tokenOut: token1,
            amountIn: amountIn,
            tradeOptions: tradeOptions,
            tickType: tickType
        )

        // Range math can occasionally produce one-sided liquidity (amountOut = 0) for native/token pairs.
        // Re-quote in full range to keep V3 available and avoid zero output values.
        if preferredTrade.amountOut == 0, tickType != .full {
            let fallbackTrade = try await quoteTrade(
                rpcSource: rpcSource,
                chain: chain,
                tokenIn: token0,
                tokenOut: token1,
                amountIn: amountIn,
                tradeOptions: tradeOptions,
                tickType: .full
            )
            return .v3(bestTrade: fallbackTrade)
        }
        return .v3(bestTrade: preferredTrade)
    }

    private func quoteTrade(
        rpcSource: RpcSource,
        chain: Chain,
        tokenIn: UniswapKit.Token,
        tokenOut: UniswapKit.Token,
        amountIn: Decimal,
        tradeOptions: TradeOptions,
        tickType: KitV3.LiquidityTickType
    ) async throws -> TradeDataV3 {
        var trade = try await kit.liquidityBestTradeExact(
            rpcSource: rpcSource,
            chain: chain,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            options: tradeOptions,
            tickType: tickType
        )

        // The SDK's full-range path returns the global TickMath limits directly.
        // Those limits may not be divisible by the selected pool's tick spacing,
        // which makes a Pancake V3 position mint revert. Re-quote using the closest
        // usable bounds, based on the fee tier selected by the first quote.
        for _ in 0 ..< 3 {
            guard let tickInfo = trade.tickInfo,
                  let bounds = usableFullRangeBounds(tickSpacing: tickInfo.tickSpacing)
            else {
                throw SwapError.invalidQuote
            }

            let lower = max(tickInfo.tickLower, bounds.lower)
            let upper = min(tickInfo.tickUpper, bounds.upper)
            guard lower < upper else {
                throw SwapError.invalidQuote
            }

            let spacing = BigInt(tickInfo.tickSpacing)
            let isAligned = tickInfo.tickLower % spacing == 0 && tickInfo.tickUpper % spacing == 0
            if lower == tickInfo.tickLower, upper == tickInfo.tickUpper, isAligned {
                return trade
            }

            trade = try await kit.liquidityBestTradeExact(
                rpcSource: rpcSource,
                chain: chain,
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountIn: amountIn,
                options: tradeOptions,
                tickType: .range(lower: lower, upper: upper)
            )
        }

        guard let tickInfo = trade.tickInfo, isUsable(tickInfo: tickInfo) else {
            throw SwapError.invalidQuote
        }
        return trade
    }

    override func transactionData(receiveAddress: EvmKit.Address, chain: Chain, trade: UniswapLiquidityAddQuote.Trade, tradeOptions: TradeOptions) async throws -> TransactionData {
        guard case let .v3(bestTrade) = trade else {
            throw SwapError.invalidTrade
        }

        let transactionData = try await kit.addLiquidityTransactionData(
            bestTrade: bestTrade,
            tradeOptions: tradeOptions,
            recipient: receiveAddress,
            rpcSource: rpcSource,
            chain: chain,
            deadline: Constants.getDeadLine()
        )

        guard let tickInfo = bestTrade.tickInfo,
              let input = LiquidityV3PositionCalldata.correctedInput(
                  transactionData.input,
                  tickLower: tickInfo.tickLower,
                  tickUpper: tickInfo.tickUpper
              )
        else {
            throw SwapError.invalidQuote
        }

        return TransactionData(to: transactionData.to, value: transactionData.value, input: input)
    }
}

extension BaseUniswapV3LiquidityAddProvider {
    var minTickValue: BigInt {
        kit.minTick
    }

    var maxTickValue: BigInt {
        kit.maxTick
    }

    func isMinimumTick(_ tick: BigInt, tickSpacing: BigUInt) -> Bool {
        guard let bounds = usableFullRangeBounds(tickSpacing: tickSpacing) else {
            return tick == minTickValue
        }
        return tick == bounds.lower
    }

    func isMaximumTick(_ tick: BigInt, tickSpacing: BigUInt) -> Bool {
        guard let bounds = usableFullRangeBounds(tickSpacing: tickSpacing) else {
            return tick == maxTickValue
        }
        return tick == bounds.upper
    }

    func isFullRange(lower: BigInt, upper: BigInt, tickSpacing: BigUInt) -> Bool {
        isMinimumTick(lower, tickSpacing: tickSpacing) && isMaximumTick(upper, tickSpacing: tickSpacing)
    }

    func isFullRange(tickInfo: TickInfo) -> Bool {
        isFullRange(lower: tickInfo.tickLower, upper: tickInfo.tickUpper, tickSpacing: tickInfo.tickSpacing)
    }

    private func usableFullRangeBounds(tickSpacing: BigUInt) -> (lower: BigInt, upper: BigInt)? {
        guard let minTick = Int(kit.minTick.description),
              let maxTick = Int(kit.maxTick.description),
              let spacing = Int(tickSpacing.description),
              let bounds = LiquidityV3TickRange.usableFullRangeBounds(minTick: minTick, maxTick: maxTick, tickSpacing: spacing)
        else {
            return nil
        }

        return (BigInt(bounds.lower), BigInt(bounds.upper))
    }

    private func isUsable(tickInfo: TickInfo) -> Bool {
        guard let bounds = usableFullRangeBounds(tickSpacing: tickInfo.tickSpacing) else {
            return false
        }

        let spacing = BigInt(tickInfo.tickSpacing)
        return tickInfo.tickLower >= bounds.lower
            && tickInfo.tickUpper <= bounds.upper
            && tickInfo.tickLower < tickInfo.tickUpper
            && tickInfo.tickLower % spacing == 0
            && tickInfo.tickUpper % spacing == 0
    }

    func tickFromPrice(price: Decimal, token0: MarketKit.Token, token1: MarketKit.Token) throws -> BigInt {
        let chain = try evmBlockchainManager.chain(blockchainType: token0.blockchainType)
        let kitToken0 = try kitToken(chain: chain, token: token0)
        let kitToken1 = try kitToken(chain: chain, token: token1)

        guard let sqrtPriceX96 = kit.encodeSqrtRatioX96(price: price, tokenA: kitToken0, tokenB: kitToken1) else {
            throw SwapError.invalidQuote
        }

        return try kit.getTickAtSqrtRatio(sqrtRatioX96: sqrtPriceX96)
    }

    func tokensSortBefore(token0: MarketKit.Token, token1: MarketKit.Token) throws -> Bool {
        let chain = try evmBlockchainManager.chain(blockchainType: token0.blockchainType)
        let kitToken0 = try kitToken(chain: chain, token: token0)
        let kitToken1 = try kitToken(chain: chain, token: token1)
        return kitToken0.address.hex.lowercased() < kitToken1.address.hex.lowercased()
    }
}
