import Foundation
import UniswapKit
import EvmKit
import MarketKit

class LiquidityProvider {
    private let swapKit: UniswapKit.Kit
    private let evmKit: EvmKit.Kit
    private let rpcSource: RpcSource
    private let isSafeSwap: Bool

    init(swapKit: UniswapKit.Kit, evmKit: EvmKit.Kit, rpcSource: RpcSource, isSafeSwap: Bool) {
        self.swapKit = swapKit
        self.evmKit = evmKit
        self.rpcSource = rpcSource
        self.isSafeSwap = isSafeSwap
    }

    private func liquidityToken(token: MarketKit.Token) throws -> UniswapKit.Token {
        switch token.type {
        case .native: return try swapKit.etherToken(chain: evmKit.chain)
        case let .eip20(address): return try swapKit.token(contractAddress: EvmKit.Address(hex: address), decimals: token.decimals)
        default: throw TokenError.unsupportedToken
        }
    }

}

extension LiquidityProvider {

    var routerAddress: EvmKit.Address {
        try! swapKit.routerAddress(chain: evmKit.chain, isSafeSwap: isSafeSwap)
    }

    var wethAddress: EvmKit.Address {
        try! swapKit.etherToken(chain: evmKit.chain).address
    }

    func swapData(tokenIn: MarketKit.Token, tokenOut: MarketKit.Token) async throws -> SwapData {
        let liquidityTokenIn = try liquidityToken(token: tokenIn)
        let liquidityTokenOut = try liquidityToken(token: tokenOut)

        return try await swapKit.swapData(rpcSource: rpcSource, chain: evmKit.chain, tokenIn: liquidityTokenIn, tokenOut: liquidityTokenOut)
    }

    func tradeData(swapData: SwapData, amount: Decimal, tradeOptions: TradeOptions) throws -> TradeData {
        return try swapKit.bestTradeExactIn(swapData: swapData, amountIn: amount, options: tradeOptions)
    }

    func transactionData(tradeData: TradeData, type: LiquidityHandleType) throws -> TransactionData {
        try swapKit.transactionLiquidityData(tradeData: tradeData, type: type, chain: evmKit.chain, recipient: evmKit.address)
    }

}

extension LiquidityProvider {

    enum TokenError: Error {
        case unsupportedToken
    }

}
