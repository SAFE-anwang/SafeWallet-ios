import Foundation
import MarketKit

protocol ILiquidityAddQuote {
    var amountOut: Decimal { get }
    var customButtonState: MultiSwapButtonState? { get }
    var settingsModified: Bool { get }
    func fields(token0: Token, token1: Token, currency: Currency, token0Rate: Decimal?, token1Rate: Decimal?) -> [MultiSwapMainField]
    func cautions() -> [CautionNew]
}
