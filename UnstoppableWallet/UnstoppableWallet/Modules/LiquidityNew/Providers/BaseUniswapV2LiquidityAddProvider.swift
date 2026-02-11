import EvmKit
import Foundation
import MarketKit
import UniswapKit

class BaseUniswapV2LiquidityAddProvider: BaseUniswapLiquidityAddProvider {
    let kit: UniswapKit.Kit

    init(kit: UniswapKit.Kit, storage: MultiSwapSettingStorage) {
        self.kit = kit

        super.init(storage: storage)
    }

    override func spenderAddress(chain: Chain) throws -> EvmKit.Address {
        try kit.routerAddress(chain: chain)
    }

    override func kitToken(chain: Chain, token: MarketKit.Token) throws -> UniswapKit.Token {
        switch token.type {
        case .native: return try kit.etherToken(chain: chain)
        case let .eip20(address): return try kit.token(contractAddress: EvmKit.Address(hex: address), decimals: token.decimals)
        default: throw SwapError.invalidToken
        }
    }

    override func trade(rpcSource: RpcSource, chain: Chain, token0 tokenIn: UniswapKit.Token, token1 tokenOut: UniswapKit.Token, amountIn: Decimal, tradeOptions: TradeOptions) async throws -> BaseUniswapLiquidityAddQuote.Trade {
        let swapData = try await kit.swapData(rpcSource: rpcSource, chain: chain, tokenIn: tokenIn, tokenOut: tokenOut)
        let tradeData = try kit.bestTradeExactIn(swapData: swapData, amountIn: amountIn, options: tradeOptions)
        return .v2(tradeData: tradeData)
    }

    override func transactionData(receiveAddress: EvmKit.Address, chain: Chain, trade: BaseUniswapLiquidityAddQuote.Trade, tradeOptions _: TradeOptions) async throws -> TransactionData {
        guard case let .v2(tradeData) = trade else {
            throw SwapError.invalidTrade
        }
        return try kit.transactionLiquidityData(tradeData: tradeData, type: .add, chain: chain, recipient: receiveAddress)
    }
}

