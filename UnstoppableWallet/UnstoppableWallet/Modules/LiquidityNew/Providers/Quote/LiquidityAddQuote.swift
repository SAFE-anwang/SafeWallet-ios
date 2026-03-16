import Foundation

class LiquidityAddQuote {
    let expectedBuyAmount: Decimal

    init(expectedBuyAmount: Decimal) {
        self.expectedBuyAmount = expectedBuyAmount
    }

    var customButtonState0: MultiSwapButtonState? {
        nil
    }
    
    var customButtonState1: MultiSwapButtonState? {
        nil
    }

    func cautions() -> [CautionNew] {
        []
    }
}
