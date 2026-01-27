import MarketKit

class PancakeV2LiquiditySwapProvider: BaseUniswapV2LiquiditySwapProvider {
    override var id: String {
        "pancake"
    }

    override var name: String {
        "PancakeSwap v.2"
    }

    override var icon: String {
        "pancake_32"
    }

    override func supports(token0: MarketKit.Token, token1: MarketKit.Token) -> Bool {
        switch (token0.blockchainType, token1.blockchainType) {
        case (.binanceSmartChain, .binanceSmartChain): return true
        default: return false
        }
    }
}
