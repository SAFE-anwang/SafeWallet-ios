import MarketKit

class PancakeV2MultiSwapProvider: BaseUniswapV2MultiSwapProvider {
    public static let id = "pancake"
    static let name = "PancakeSwap v.2"
    override var id: String { Self.id }
    override var name: String { Self.name }
    override var type: SwapProviderType { .excellent }
    override var icon: String { "swap_provider_pancake" }

    override func supports(tokenIn: MarketKit.Token, tokenOut: MarketKit.Token) -> Bool {
        switch (tokenIn.blockchainType, tokenOut.blockchainType) {
        case (.binanceSmartChain, .binanceSmartChain): return true
        default: return false
        }
    }
}
