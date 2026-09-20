import MarketKit

class QuickSwapMultiSwapProvider: BaseUniswapV2MultiSwapProvider {
    public static let id = "quickswap"
    static let name = "QuickSwap"
    override var id: String { Self.id }
    override var name: String { Self.name }
    override var type: SwapProviderType { .excellent }
    override var icon: String { "swap_provider_quick" }

    override func supports(tokenIn: MarketKit.Token, tokenOut: MarketKit.Token) -> Bool {
        switch (tokenIn.blockchainType, tokenOut.blockchainType) {
        case (.polygon, .polygon): return true
        default: return false
        }
    }
}
