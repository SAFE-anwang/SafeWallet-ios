import MarketKit

class UniswapV2LiquidityAddProvider: BaseUniswapV2LiquidityAddProvider {
    override var id: String {
        "uniswap"
    }

    override var name: String {
        "Uniswap v.2"
    }

    override var icon: String {
        "uniswap_32"
    }

    override func supports(token0 tokenIn: MarketKit.Token, token1 tokenOut: MarketKit.Token) -> Bool {
        switch (tokenIn.blockchainType, tokenOut.blockchainType) {
        case (.ethereum, .ethereum): return true
        default: return false
        }
    }
}
