import EvmKit
import MarketKit
import UniswapKit
import Foundation

class SafeSwapMultiSwapProvider: BaseUniswapV2MultiSwapProvider {
    override var id: String { "SafeSwap" }
    override var name: String { "SafeSwap" }
    override var type: SwapProviderType { .flexible }
    override var icon: String { "safelog" }

    override func spenderAddress(chain: Chain) throws -> EvmKit.Address {
        try kit.routerAddress(chain: chain, isSafeSwap: true)
    }

    override func supports(tokenIn: MarketKit.Token, tokenOut: MarketKit.Token) -> Bool {
        switch (tokenIn.blockchainType, tokenOut.blockchainType) {
        case (.ethereum, .ethereum): return true
        case (.binanceSmartChain, .binanceSmartChain): return true
        case (.polygon, .polygon): return true
        case (.safe4, .safe4): return true
        default: return false
        }
    }

    override func trade(rpcSource: RpcSource, chain: Chain, tokenIn: UniswapKit.Token, tokenOut: UniswapKit.Token, amountIn: Decimal, tradeOptions: TradeOptions) async throws -> UniswapMultiSwapQuote.Trade {
        let swapData = try await kit.swapData(rpcSource: rpcSource, chain: chain, tokenIn: tokenIn, tokenOut: tokenOut)
        let tradeData = try kit.bestTradeExactIn(swapData: swapData, amountIn: amountIn, options: tradeOptions)
        return .v2(tradeData: tradeData)
    }

    override func transactionData(receiveAddress: EvmKit.Address, chain: Chain, trade: UniswapMultiSwapQuote.Trade, tradeOptions: TradeOptions) throws -> TransactionData {
        guard case let .v2(tradeData) = trade else {
            throw SwapError.invalidTrade
        }

        return try kit.transactionData(receiveAddress: receiveAddress, chain: chain, tradeData: tradeData)
    }
}
