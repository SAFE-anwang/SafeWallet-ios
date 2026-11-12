import BigInt
import EvmKit
import Foundation
import MarketKit
import Testing
@testable import UniswapKit
@testable import WalletCore

struct LiquidityV2ApprovalAmountTests {
    @Test(arguments: [6, 8, 18])
    func approvalMatchesActualV2CalldataWhenMidPriceLosesPrecision(decimals: Int) throws {
        let fixture = try fixture(decimals: decimals)
        let transaction = try fixture.kit.transactionLiquidityData(tradeData: fixture.trade, type: .add, chain: .binanceSmartChain, recipient: fixture.recipient)
        let encodedAmount = BigUInt(Data(transaction.input[(4 + 3 * 32) ..< (4 + 4 * 32)]))
        let legacyAmount = try #require(fixture.trade.amountIn) * #require(fixture.trade.midPrice)
        let legacyApproval = fixture.tokenOut.fractionalMonetaryValue(value: legacyAmount)

        // This is real UniswapKit calldata, not a reconstruction of its formula.
        #expect(encodedAmount > legacyApproval)
        let required = try LiquidityV2ApprovalAmount.requiredAmount(
            kit: fixture.kit, tradeData: fixture.trade, chain: .binanceSmartChain, tokenOut: fixture.tokenOut
        )
        #expect(fixture.tokenOut.fractionalMonetaryValue(value: required) == encodedAmount)
    }

    @Test(arguments: [true, false])
    func nativePairUsesEncodedTokenAmountOrTransactionValue(nativeInput: Bool) throws {
        let fixture = try fixture(decimals: 18, nativeInput: nativeInput)
        let transaction = try fixture.kit.transactionLiquidityData(tradeData: fixture.trade, type: .add, chain: .binanceSmartChain, recipient: fixture.recipient)
        let encodedAmount = nativeInput
            ? BigUInt(Data(transaction.input[(4 + 32) ..< (4 + 2 * 32)]))
            : transaction.value
        let required = try LiquidityV2ApprovalAmount.requiredAmount(
            kit: fixture.kit, tradeData: fixture.trade, chain: .binanceSmartChain, tokenOut: fixture.tokenOut
        )
        #expect(fixture.tokenOut.fractionalMonetaryValue(value: required) == encodedAmount)
    }

    private func fixture(decimals: Int, nativeInput: Bool? = nil) throws -> (kit: UniswapKit.Kit, trade: TradeData, tokenOut: MarketKit.Token, recipient: EvmKit.Address) {
        let kit = try UniswapKit.Kit.instance()
        let address0 = try EvmKit.Address(hex: "0x0000000000000000000000000000000000000001")
        let address1 = try EvmKit.Address(hex: "0x0000000000000000000000000000000000000002")
        let token0 = nativeInput == true ? try kit.etherToken(chain: .binanceSmartChain) : kit.token(contractAddress: address0, decimals: decimals)
        let token1 = nativeInput == false ? try kit.etherToken(chain: .binanceSmartChain) : kit.token(contractAddress: address1, decimals: decimals)
        let scale = BigUInt(10).power(decimals)
        let pair = Pair(
            reserve0: TokenAmount(token: token0, rawAmount: 300 * scale),
            reserve1: TokenAmount(token: token1, rawAmount: 100 * scale)
        )
        let swapData = SwapData(pairs: [pair], tokenIn: token0, tokenOut: token1)
        let amountIn = Decimal(10) + Decimal(sign: .plus, exponent: -decimals, significand: 1)
        let trade = try kit.bestTradeExactIn(swapData: swapData, amountIn: amountIn)
        let tokenOut = MarketKit.Token(
            coin: Coin(uid: "approval-output", name: "Output", code: "OUT"),
            blockchain: Blockchain(type: .binanceSmartChain, name: "BSC", explorerUrl: nil),
            type: nativeInput == false ? .native : .eip20(address: address1.eip55),
            decimals: decimals
        )
        return (kit, trade, tokenOut, address0)
    }
}
