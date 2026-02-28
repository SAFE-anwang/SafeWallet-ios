import Foundation
import MarketKit

class BaseEvmLiquidityAddQuote: ILiquidityAddQuote {
    let allowanceState: LiquidityAddAllowanceHelper.AllowanceState

    init(allowanceState: LiquidityAddAllowanceHelper.AllowanceState) {
        self.allowanceState = allowanceState
    }

    var amountOut: Decimal {
        fatalError("Must be implemented in subclass")
    }

    var customButtonState: MultiSwapButtonState? {
        allowanceState.customButtonState
    }

    var settingsModified: Bool {
        false
    }

    func cautions() -> [CautionNew] {
        var cautions = [CautionNew]()
        cautions.append(contentsOf: allowanceState.cautions())
        return cautions
    }

    func fields(token0 _: Token, token1 _: Token, currency _: Currency, token0Rate _: Decimal?, token1Rate _: Decimal?) -> [MultiSwapMainField] {
        var fields = [MultiSwapMainField]()
        fields.append(contentsOf: allowanceState.fields())
        return fields
    }
}
