import MarketKit

class PancakeV3LiquidityAddProvider: BaseUniswapV3LiquidityAddProvider {
    override var id: String {
        "pancake_v3"
    }

    override var name: String {
        "PancakeSwap v.3"
    }

    override var icon: String {
        "swap_provider_pancake"
    }

    override func supports(token0: MarketKit.Token, token1: MarketKit.Token) -> Bool {
        guard token0.blockchainType == token1.blockchainType else {
            return false
        }
        
        switch (token0.blockchainType, token1.blockchainType) {
        case (.binanceSmartChain, .binanceSmartChain): return token0.type != .native && token1.type != .native
        default: return false
        }
    }
}
