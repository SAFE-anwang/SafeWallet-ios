import Foundation
import MarketKit
import Testing
@testable import WalletCore

struct LiquidityAddQuoteApprovalAmountTests {
    private func token(decimals: Int) -> Token {
        Token(
            coin: Coin(uid: "approval-test", name: "Approval Test", code: "TEST"),
            blockchain: Blockchain(type: .binanceSmartChain, name: "BSC", explorerUrl: nil),
            type: .eip20(address: "0x0000000000000000000000000000000000000001"),
            decimals: decimals
        )
    }

    @Test(arguments: [6, 8, 18])
    func exactApprovalCoversPoolRatioWithExtraFractionalDigits(decimals: Int) async {
        let token = token(decimals: decimals)
        let unit = Decimal(sign: .plus, exponent: -decimals, significand: 1)
        let quotedAmount = 1 + unit / 10
        let confirmedAllowance = token.decimalValue(value: token.fractionalMonetaryValue(value: quotedAmount))

        // Before the fix, a confirmed exact approval remained below the quote.
        #expect(confirmedAllowance < quotedAmount)
        let requiredAmount = LiquidityAddAllowanceHelper.requiredAmount(token: token, amount: quotedAmount)
        #expect(requiredAmount == 1)
        #expect(confirmedAllowance >= requiredAmount)

        let helper = LiquidityAddAllowanceHelper { _ in
            StubAllowanceAdapter(value: confirmedAllowance)
        }
        let state = await helper.allowanceState(spenderAddress: Address(raw: "spender"), token: token, amount: quotedAmount)
        guard case .allowed = state else {
            Issue.record("A confirmed exact approval must remove the approval button")
            return
        }
        #expect(state.customButtonState == nil)
    }

    @Test(arguments: [6, 8, 18])
    func roundingMatchesApprovalEncodingWithoutIgnoringOneUnitShortfall(decimals: Int) async {
        let token = token(decimals: decimals)
        let unit = Decimal(sign: .plus, exponent: -decimals, significand: 1)
        let quotedAmount = 1 + unit * Decimal(string: "0.6")!
        let requiredAmount = LiquidityAddAllowanceHelper.requiredAmount(token: token, amount: quotedAmount)
        let confirmedAllowance = token.decimalValue(value: token.fractionalMonetaryValue(value: quotedAmount))

        #expect(requiredAmount == 1 + unit)
        #expect(confirmedAllowance == requiredAmount)

        // Both a revoked allowance and an allowance one unit short must still
        // require approval; no floating-point tolerance may bypass this check.
        for allowance in [Decimal.zero, confirmedAllowance - unit] {
            let helper = LiquidityAddAllowanceHelper { _ in
                StubAllowanceAdapter(value: allowance)
            }
            let state = await helper.allowanceState(spenderAddress: Address(raw: "spender"), token: token, amount: quotedAmount)
            guard case .notEnough = state else {
                Issue.record("An insufficient allowance must require approval")
                continue
            }
            #expect(state.customButtonState != nil)
        }
    }

    @Test func normalizedApprovalAmountIsStableAcrossQuoteRefreshes() {
        let token = token(decimals: 18)
        let amount = Decimal(string: "12.345678901234567890123456")!
        let requiredAmount = LiquidityAddAllowanceHelper.requiredAmount(token: token, amount: amount)

        #expect(LiquidityAddAllowanceHelper.requiredAmount(token: token, amount: requiredAmount) == requiredAmount)
    }

    @Test func requiredApprovalAmountIsSeparateFromDisplayedQuoteOutput() {
        let quote = EvmLiquidityAddQuote(
            expectedBuyAmount: Decimal(97),
            requiredAmount1: Decimal(100),
            allowanceState0: .allowed,
            allowanceState1: .allowed
        )

        #expect(quote.expectedBuyAmount == Decimal(97))
        #expect(quote.requiredAmount1 == Decimal(100))
    }
}

private struct StubAllowanceAdapter: IAllowanceAdapter {
    let value: Decimal
    var pendingTransactions: [TransactionRecord] { [] }

    func allowance(spenderAddress _: Address, defaultBlockParameter _: BlockParameter) async throws -> Decimal {
        value
    }
}
