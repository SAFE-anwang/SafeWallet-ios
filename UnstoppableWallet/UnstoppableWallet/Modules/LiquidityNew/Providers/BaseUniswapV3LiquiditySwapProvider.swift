import EvmKit
import Foundation
import MarketKit
import UniswapKit

class BaseUniswapV3LiquiditySwapProvider: BaseUniswapLiquiditySwapProvider {
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

    override func trade(rpcSource: RpcSource, chain: Chain, token0: UniswapKit.Token, token1: UniswapKit.Token, amountIn: Decimal, tradeOptions: TradeOptions) async throws -> BaseUniswapLiquiditySwapQuote.Trade {
        let bestTrade = try await kit.liquidityBestTradeExact(rpcSource: rpcSource, chain: chain, tokenIn: token0, tokenOut: token1, amountIn: amountIn, options: tradeOptions, tickType: tickType)
//        let bestTrade = try await kit.bestTradeExactIn(rpcSource: rpcSource, chain: chain, tokenIn: tokenIn, tokenOut: tokenOut, amountIn: amountIn, options: tradeOptions)
        return .v3(bestTrade: bestTrade)
    }

    override func transactionData(receiveAddress: EvmKit.Address, chain: Chain, trade: BaseUniswapLiquiditySwapQuote.Trade, tradeOptions: TradeOptions) async throws -> TransactionData {
        guard case let .v3(bestTrade) = trade else {
            throw SwapError.invalidTrade
        }
        return try await kit.addLiquidityTransactionData(bestTrade: bestTrade, tradeOptions: tradeOptions, recipient: receiveAddress, rpcSource: rpcSource, chain: chain, deadline: Constants.getDeadLine())
    }
}
