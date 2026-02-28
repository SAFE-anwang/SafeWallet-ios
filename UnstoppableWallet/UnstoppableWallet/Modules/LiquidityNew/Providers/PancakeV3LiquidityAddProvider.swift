import MarketKit

class PancakeV3LiquidityAddProvider: BaseUniswapV3LiquidityAddProvider {
    override var id: String {
        "pancake_v3"
    }

    override var name: String {
        "PancakeSwap v.3"
    }

    override var icon: String {
        "pancake_32"
    }

    override func supports(token0: MarketKit.Token, token1: MarketKit.Token) -> Bool {
        guard token0.blockchainType == token1.blockchainType else {
            return false
        }

        switch token0.blockchainType {
        case .binanceSmartChain: return true
        default: return false
        }
    }
}
