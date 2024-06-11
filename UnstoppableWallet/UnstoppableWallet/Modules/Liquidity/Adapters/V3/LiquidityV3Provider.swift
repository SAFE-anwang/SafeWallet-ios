import EvmKit
import Foundation
import MarketKit
import UniswapKit
import BigInt

class LiquidityV3Provider {
    private let swapKit: UniswapKit.KitV3
    private let evmKit: EvmKit.Kit
    private let rpcSource: RpcSource

    init(swapKit: UniswapKit.KitV3, evmKit: EvmKit.Kit, rpcSource: RpcSource) {
        self.swapKit = swapKit
        self.evmKit = evmKit
        self.rpcSource = rpcSource
    }

    private func uniswapToken(token: MarketKit.Token) throws -> UniswapKit.Token {
        switch token.type {
        case .native: return try swapKit.etherToken(chain: evmKit.chain)
        case let .eip20(address): return try swapKit.token(contractAddress: EvmKit.Address(hex: address), decimals: token.decimals)
        default: throw TokenError.unsupportedToken
        }
    }
}

extension LiquidityV3Provider {
    
//    var routerAddress: EvmKit.Address {
//        swapKit.routerAddress(chain: evmKit.chain)
//    }
    
    var nonfungiblePositionAddress: EvmKit.Address {
        swapKit.nonfungiblePositionAddress(chain: evmKit.chain)
    }

    var wethAddress: EvmKit.Address {
        try! swapKit.etherToken(chain: evmKit.chain).address
    }

    func bestTrade(tokenIn: MarketKit.Token, tokenOut: MarketKit.Token, amount: Decimal, tradeOptions: TradeOptions, tickType: UniswapKit.KitV3.LiquidityTickType) async throws -> TradeDataV3 {
        
        let uniswapTokenIn = try uniswapToken(token: tokenIn)
        let uniswapTokenOut = try uniswapToken(token: tokenOut)
        return try await swapKit.liquidityBestTradeExact(rpcSource: rpcSource, chain: evmKit.chain, tokenIn: uniswapTokenIn, tokenOut: uniswapTokenOut, amountIn: amount, options: tradeOptions, tickType: tickType)
    }

    func transactionData(tradeData: TradeDataV3, tradeOptions: TradeOptions) async throws -> TransactionData {
        try await swapKit.addLiquidityTransactionData(bestTrade: tradeData, tradeOptions: tradeOptions, recipient: evmKit.address, rpcSource: rpcSource, chain: evmKit.chain, deadline: Constants.getDeadLine())
    }
}

extension LiquidityV3Provider {
    enum TokenError: Error {
        case unsupportedToken
    }
}
