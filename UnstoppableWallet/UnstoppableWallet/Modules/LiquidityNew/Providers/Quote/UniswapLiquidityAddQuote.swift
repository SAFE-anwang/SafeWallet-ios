import Foundation
import MarketKit
import UniswapKit

class UniswapLiquidityAddQuote: EvmLiquidityAddQuote {
    let trade: Trade
    let tradeOptions: TradeOptions
    let providerName: String

    init(trade: Trade, tradeOptions: TradeOptions, providerName: String, allowanceState0: LiquidityAddAllowanceHelper.AllowanceState, allowanceState1: LiquidityAddAllowanceHelper.AllowanceState) {
        self.trade = trade
        self.tradeOptions = tradeOptions
        self.providerName = providerName

        super.init(expectedBuyAmount: trade.amountOut ?? 0, allowanceState0: allowanceState0, allowanceState1: allowanceState1)
    }
}

extension UniswapLiquidityAddQuote {
    enum Trade {
        case v2(tradeData: TradeData)
        case v3(bestTrade: TradeDataV3)

        var amountOut: Decimal? {
            switch self {
            case let .v2(tradeData): return tradeData.amountOut
            case let .v3(bestTrade): return bestTrade.amountOut
            }
        }

        var priceImpact: Decimal? {
            switch self {
            case let .v2(tradeData): return tradeData.priceImpact.map { max(0, $0) }
            case let .v3(bestTrade): return bestTrade.priceImpact.map { max(0, $0) }
            }
        }
    }
}

