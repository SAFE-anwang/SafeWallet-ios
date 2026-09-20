import MarketKit

class UniswapV2MultiSwapProvider: BaseUniswapV2MultiSwapProvider {
    public static let id = "uniswap"
    static let name = "Uniswap v.2"
    override var id: String { Self.id }
    override var name: String { Self.name }
    override var type: SwapProviderType { .excellent }
    override var icon: String { "swap_provider_uniswap" }

    override func supports(tokenIn: MarketKit.Token, tokenOut: MarketKit.Token) -> Bool {
        switch (tokenIn.blockchainType, tokenOut.blockchainType) {
        case (.ethereum, .ethereum): return true
        case (.base, .base): return true
        default: return false
        }
    }
}
