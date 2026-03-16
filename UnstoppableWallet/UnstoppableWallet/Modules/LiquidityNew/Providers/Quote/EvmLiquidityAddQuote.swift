import Foundation

class EvmLiquidityAddQuote: LiquidityAddQuote {
    let allowanceState0: LiquidityAddAllowanceHelper.AllowanceState
    let allowanceState1: LiquidityAddAllowanceHelper.AllowanceState
    init(expectedBuyAmount: Decimal, allowanceState0: LiquidityAddAllowanceHelper.AllowanceState, allowanceState1: LiquidityAddAllowanceHelper.AllowanceState) {
        self.allowanceState0 = allowanceState0
        self.allowanceState1 = allowanceState1
        super.init(expectedBuyAmount: expectedBuyAmount)
    }

    override var customButtonState0: MultiSwapButtonState? {
        allowanceState0.customButtonState
    }
    
    override var customButtonState1: MultiSwapButtonState? {
        allowanceState1.customButtonState
    }

    override func cautions() -> [CautionNew] {
        allowanceState0.cautions() + allowanceState1.cautions()
    }
}
