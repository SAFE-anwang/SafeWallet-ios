import Foundation
import Testing
@testable import WalletCore

struct LiquidityAddQuoteApprovalAmountTests {
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
