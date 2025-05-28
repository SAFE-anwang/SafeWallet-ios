import EvmKit
import Foundation
import MarketKit
import UniswapKit

class UniswapProvider {
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

    private func uniswapToken(token: MarketKit.Token) throws -> UniswapKit.Token {
        switch token.type {
        case .native: return try swapKit.etherToken(chain: evmKit.chain)
        case let .eip20(address): return try swapKit.token(contractAddress: EvmKit.Address(hex: address), decimals: token.decimals)
        default: throw TokenError.unsupportedToken
        }
    }
}

extension UniswapProvider {
    var routerAddress: EvmKit.Address {
        try! swapKit.routerAddress(chain: evmKit.chain, isSafeSwap: isSafeSwap)
    }

    var wethAddress: EvmKit.Address {
        try! swapKit.etherToken(chain: evmKit.chain).address
    }

    func swapData(tokenIn: MarketKit.Token, tokenOut: MarketKit.Token) async throws -> SwapData {
        let uniswapTokenIn = try uniswapToken(token: tokenIn)
        let uniswapTokenOut = try uniswapToken(token: tokenOut)

        return try await swapKit.swapData(rpcSource: rpcSource, chain: evmKit.chain, tokenIn: uniswapTokenIn, tokenOut: uniswapTokenOut)
    }

    func tradeData(swapData: SwapData, amount: Decimal, tradeType: TradeType, tradeOptions: TradeOptions) throws -> TradeData {
        switch tradeType {
        case .exactIn:
            return try swapKit.bestTradeExactIn(swapData: swapData, amountIn: amount, options: tradeOptions)
        case .exactOut:
            return try swapKit.bestTradeExactOut(swapData: swapData, amountOut: amount, options: tradeOptions)
        }
    }

    func transactionData(tradeData: TradeData) throws -> TransactionData {
        try swapKit.transactionData(receiveAddress: evmKit.receiveAddress, chain: evmKit.chain, tradeData: tradeData)
    }
}

extension UniswapProvider {
    enum TokenError: Error {
        case unsupportedToken
    }
}
