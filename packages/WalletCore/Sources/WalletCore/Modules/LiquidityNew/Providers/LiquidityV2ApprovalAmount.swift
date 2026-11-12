import BigInt
import EvmKit
import Foundation
import MarketKit
import UniswapKit

enum LiquidityV2ApprovalAmount {
    static func requiredAmount(kit: UniswapKit.Kit, tradeData: TradeData, chain: Chain, tokenOut: MarketKit.Token) throws -> Decimal {
        // Encode locally with the same kit used for submission. The recipient
        // does not affect amounts; this transaction is never sent.
        let transaction = try kit.transactionLiquidityData(
            tradeData: tradeData,
            type: .add,
            chain: chain,
            recipient: EvmKit.Address(raw: Data(repeating: 0, count: 20))
        )
        let input = transaction.input
        let selector = Data(input.prefix(4))
        let rawAmount: BigUInt

        if selector == ContractMethodHelper.methodId(signature: AddLiquidityMethod.methodSignature),
           input.count == 4 + 8 * 32,
           !tokenOut.type.isNative
        {
            // addLiquidity: tokenA, tokenB, amountADesired, amountBDesired, ...
            rawAmount = BigUInt(Data(input[(4 + 3 * 32) ..< (4 + 4 * 32)]))
        } else if selector == ContractMethodHelper.methodId(signature: AddLiquidityEthMethod.methodSignature),
                  input.count == 4 + 6 * 32
        {
            // addLiquidityETH: token, amountTokenDesired, ...; native amount is value.
            rawAmount = tokenOut.type.isNative ? transaction.value : BigUInt(Data(input[(4 + 32) ..< (4 + 2 * 32)]))
        } else {
            throw BaseUniswapLiquidityAddProvider.SwapError.invalidQuote
        }

        guard let amount = Decimal(bigUInt: rawAmount, decimals: tokenOut.decimals) else {
            throw BaseUniswapLiquidityAddProvider.SwapError.invalidQuote
        }
        return amount
    }
}
