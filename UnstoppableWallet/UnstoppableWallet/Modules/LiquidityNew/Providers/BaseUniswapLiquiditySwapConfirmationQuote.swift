import EvmKit
import Foundation
import MarketKit

class BaseUniswapLiquiditySwapConfirmationQuote: BaseEvmLiquiditySwapConfirmationQuote {
    let quote: BaseUniswapLiquiditySwapQuote
    let transactionData: TransactionData?
    let transactionError: Error?

    init(quote: BaseUniswapLiquiditySwapQuote, transactionData: TransactionData?, transactionError: Error?, gasPrice: GasPrice?, evmFeeData: EvmFeeData?, nonce: Int?) {
        self.quote = quote
        self.transactionData = transactionData
        self.transactionError = transactionError

        super.init(gasPrice: gasPrice, evmFeeData: evmFeeData, nonce: nonce)
    }

    override var amountOut: Decimal {
        quote.trade.amountOut ?? 0
    }

    override var canSwap: Bool {
        super.canSwap && transactionData != nil
    }

    override func cautions(baseToken: MarketKit.Token) -> [CautionNew] {
        var cautions = super.cautions(baseToken: baseToken)

        if let transactionError {
            cautions.append(caution(transactionError: transactionError, feeToken: baseToken))
        }

        cautions.append(contentsOf: quote.cautions())

        return cautions
    }

    override func priceSectionFields(token0: MarketKit.Token, token1: MarketKit.Token, baseToken: MarketKit.Token, currency: Currency, token0Rate: Decimal?, token1Rate: Decimal?, baseTokenRate: Decimal?) -> [SendField] {
        var fields = super.priceSectionFields(token0: token0, token1: token1, baseToken: baseToken, currency: currency, token0Rate: token0Rate, token1Rate: token1Rate, baseTokenRate: baseTokenRate)

        if let priceImpact = quote.trade.priceImpact, BaseUniswapLiquiditySwapProvider.PriceImpactLevel(priceImpact: priceImpact) != .negligible {
            fields.append(.priceImpact(priceImpact))
        }

        if let recipient = quote.recipient {
            fields.append(.recipient(recipient.title, blockchainType: token1.blockchainType))
        }

        let slippage = quote.tradeOptions.allowedSlippage
        fields.append(.slippage(slippage))

        let minAmountOut = amountOut * (1 - slippage / 100)

        fields.append(
            .value(
                title: "swap.confirmation.minimum_received".localized,
                description: nil,
                appValue: AppValue(token: token1, value: minAmountOut),
                currencyValue: token1Rate.map { CurrencyValue(currency: currency, value: minAmountOut * $0) },
                formatFull: true
            )
        )

        return fields
    }
}

