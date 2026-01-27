import Foundation
import MarketKit

class BaseEvmLiquiditySwapConfirmationQuote: BaseSendEvmData, ILiquiditySwapConfirmationQuote {
    var amountOut: Decimal {
        fatalError("Must be implemented in subclass")
    }

    var feeData: FeeData? {
        evmFeeData.map { .evm(evmFeeData: $0) }
    }

    var canSwap: Bool {
        gasPrice != nil && evmFeeData != nil
    }

    func cautions(baseToken _: Token) -> [CautionNew] {
        []
    }

    func priceSectionFields(token0 _: Token, token1 _: Token, baseToken _: Token, currency _: Currency, token0Rate _: Decimal?, token1Rate _: Decimal?, baseTokenRate _: Decimal?) -> [SendField] {
        []
    }

    func otherSections(token0: Token, token1: Token, baseToken: Token, currency: Currency, token0Rate: Decimal?, token1Rate: Decimal?, baseTokenRate: Decimal?) -> [SendDataSection] {
        var sections = [SendDataSection]()

        if let nonce {
            sections.append(
                .init([
                    .levelValue(title: "send.confirmation.nonce".localized, value: String(nonce), level: .regular),
                ])
            )
        }

        let additionalFeeFields = additionalFeeFields(token0: token0, token1: token1, baseToken: baseToken, currency: currency, token0Rate: token0Rate, token1Rate: token1Rate, baseTokenRate: baseTokenRate)
        sections.append(.init(feeFields(feeToken: baseToken, currency: currency, feeTokenRate: baseTokenRate) + additionalFeeFields))

        return sections
    }

    func additionalFeeFields(token0 _: Token, token1 _: Token, baseToken _: Token, currency _: Currency, token0Rate _: Decimal?, token1Rate _: Decimal?, baseTokenRate _: Decimal?) -> [SendField] {
        []
    }
}
