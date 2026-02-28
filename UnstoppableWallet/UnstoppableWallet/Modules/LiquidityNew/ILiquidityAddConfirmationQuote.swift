import Foundation
import MarketKit

protocol ILiquidityAddConfirmationQuote {
    var amountOut: Decimal { get }
    var feeData: FeeData? { get }
    var canSwap: Bool { get }
    func cautions(baseToken: Token) -> [CautionNew]
    func priceSectionFields(token0: Token, token1: Token, baseToken: Token, currency: Currency, token0Rate: Decimal?, token1Rate: Decimal?, baseTokenRate: Decimal?) -> [SendField]
    func otherSections(token0: Token, token1: Token, baseToken: Token, currency: Currency, token0Rate: Decimal?, token1Rate: Decimal?, baseTokenRate: Decimal?) -> [SendDataSection]
}
