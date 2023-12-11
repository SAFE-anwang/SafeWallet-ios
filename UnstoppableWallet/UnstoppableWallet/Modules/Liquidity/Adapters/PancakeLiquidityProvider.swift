import Foundation
import UniswapKit
import EvmKit
import MarketKit

class PancakeLiquidityProvider {
    private let pancakeSwapKit: UniswapKit.Kit

    init(swapKit: UniswapKit.Kit) {
        self.pancakeSwapKit = swapKit
    }

    private func liquidityToken(token: MarketKit.Token) throws -> UniswapKit.Token {
        switch token.type {
        case .native: return pancakeSwapKit.etherToken
        case let .eip20(address): return pancakeSwapKit.token(contractAddress: try EvmKit.Address(hex: address), decimals: token.decimals)
        default: throw TokenError.unsupportedToken
        }
    }

}

extension PancakeLiquidityProvider {

    var routerAddress: EvmKit.Address {
        pancakeSwapKit.routerAddress
    }

    var wethAddress: EvmKit.Address {
        pancakeSwapKit.etherToken.address
    }

    func swapData(tokenIn: MarketKit.Token, tokenOut: MarketKit.Token) async throws -> SwapData {
        let liquidityTokenIn = try liquidityToken(token: tokenIn)
        let liquidityTokenOut = try liquidityToken(token: tokenOut)

        return try await pancakeSwapKit.swapData(tokenIn: liquidityTokenIn, tokenOut: liquidityTokenOut)
    }

    func tradeData(swapData: SwapData, amount: Decimal, /* tradeType: TradeType,*/ tradeOptions: TradeOptions) throws -> TradeData {
//        switch tradeType {
//        case .exactIn:
            return try pancakeSwapKit.bestTradeExactIn(swapData: swapData, amountIn: amount, options: tradeOptions)
//        case .exactOut:
//            return try pancakeSwapKit.bestTradeExactOut(swapData: swapData, amountOut: amount, options: tradeOptions)
//        }
    }

    func transactionData(tradeData: TradeData, type: LiquidityHandleType) throws -> TransactionData {
        try pancakeSwapKit.transactionLiquidityData(tradeData: tradeData, type: type)
    }

}

extension PancakeLiquidityProvider {

    enum TokenError: Error {
        case unsupportedToken
    }

}
