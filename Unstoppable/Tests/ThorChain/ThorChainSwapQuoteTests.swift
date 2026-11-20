import Foundation
import ObjectMapper
import Testing
@testable import WalletCore

struct ThorChainSwapQuoteTests {
    @Test func nativeQuoteDecodesWithoutAnInboundAddress() throws {
        try checkQuote(chain: "thorchain", kind: "cosmos_memo", inboundAddress: nil)
    }

    @Test func quoteFromAnotherChainKeepsItsInboundAddress() throws {
        try checkQuote(chain: "bitcoin", kind: "transfer", inboundAddress: "bc1qvault")
    }

    private func checkQuote(chain: String, kind: String, inboundAddress: String?) throws {
        let memo = "=:BTC.BTC:bc1qexample"
        var execution: [String: Any] = [
            "method": "thorchain_deposit", "chain": chain, "memo": memo, "delivery": ["kind": kind],
        ]
        execution["inboundAddress"] = inboundAddress
        let quote = try USwapMultiSwapApi.SwapResponseMapping(JSON: [
            "expectedBuyAmount": "0.12345678", "execution": execution,
        ]).response

        #expect(quote.expectedBuyAmount == Decimal(string: "0.12345678"))
        guard case let .thorchainDeposit(parsedChain, address, parsedMemo, delivery) = quote.execution else {
            Issue.record("Expected a THORChain deposit")
            return
        }
        #expect(parsedChain == chain)
        #expect(address == (inboundAddress ?? ""))
        #expect(parsedMemo == memo)
        #expect(delivery.kind == kind)
    }
}
