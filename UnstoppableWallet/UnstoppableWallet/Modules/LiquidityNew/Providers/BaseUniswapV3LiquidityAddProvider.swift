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
        return try await kit.liquidityBestTradeExact(
            rpcSource: rpcSource,
            chain: chain,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            options: tradeOptions,
            tickType: tickType
        )
    }

    override func transactionData(receiveAddress: EvmKit.Address, chain: Chain, trade: UniswapLiquidityAddQuote.Trade, tradeOptions: TradeOptions) async throws -> TransactionData {
        guard case let .v3(bestTrade) = trade else {
            throw SwapError.invalidTrade
        }
        return try await kit.addLiquidityTransactionData(bestTrade: bestTrade, tradeOptions: tradeOptions, recipient: receiveAddress, rpcSource: rpcSource, chain: chain, deadline: Constants.getDeadLine())
    }
}

extension BaseUniswapV3LiquidityAddProvider {
    var minTickValue: BigInt {
        kit.minTick
    }

    var maxTickValue: BigInt {
        kit.maxTick
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
