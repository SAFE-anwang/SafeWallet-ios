import Foundation

class LiquidityMainViewModel {
    private(set) var dexManager: ILiquidityDexManager

    init(dexManager: ILiquidityDexManager) {
        self.dexManager = dexManager
    }

}
