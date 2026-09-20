import EvmKit
import Foundation
import MarketKit
import UniswapKit

class BaseUniswapV2MultiSwapProvider: BaseUniswapMultiSwapProvider {
    let kit: UniswapKit.Kit

    init(kit: UniswapKit.Kit) {
        self.kit = kit

        super.init()
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

    override func trade(rpcSource: RpcSource, chain: Chain, tokenIn: UniswapKit.Token, tokenOut: UniswapKit.Token, amountIn: Decimal, tradeOptions: TradeOptions) async throws -> UniswapMultiSwapQuote.Trade {
        let swapData = try await kit.swapData(rpcSource: rpcSource, chain: chain, tokenIn: tokenIn, tokenOut: tokenOut)
        let tradeData = try kit.bestTradeExactIn(swapData: swapData, amountIn: amountIn, options: tradeOptions)
        return .v2(tradeData: tradeData)
    }

    override func transactionData(receiveAddress: EvmKit.Address, chain: Chain, trade: UniswapMultiSwapQuote.Trade, tradeOptions _: TradeOptions) throws -> TransactionData {
        guard case let .v2(tradeData) = trade else {
            throw SwapError.invalidTrade
        }

        return try kit.transactionData(receiveAddress: receiveAddress, chain: chain, tradeData: tradeData)
    }

    /// V2 providers execute directly on-chain and are not tracked by uswap-server.
    /// Resolve their pending history from the active EVM kit instead of inheriting the
    /// base provider's fatal placeholder.
    override public func track(swap: Swap) async throws -> Swap {
        guard let transactionHash = swap.txHash?.hs.hexData,
              let evmKitWrapper = ChildWalletBridge.shared.activeEvmKitWrapper(blockchainType: swap.tokenIn.blockchainType),
              let transaction = evmKitWrapper.evmKit.transaction(hash: transactionHash)
        else {
            return swap
        }

        var updatedSwap = swap
        if transaction.transaction.isFailed {
            updatedSwap.status = .failed
        } else if transaction.transaction.blockNumber != nil {
            updatedSwap.status = .completed
        }

        return updatedSwap
    }
}
