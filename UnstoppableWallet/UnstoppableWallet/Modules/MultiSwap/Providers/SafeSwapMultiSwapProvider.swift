import EvmKit
import MarketKit

class SafeSwapMultiSwapProvider: BaseUniswapV2MultiSwapProvider {
    override var id: String {
        "SafeSwap"
    }

    override var name: String {
        "SafeSwap"
    }

    override var icon: String {
        "safelog"
    }

    override func spenderAddress(chain: Chain) throws -> EvmKit.Address {
        try kit.routerAddress(chain: chain, isSafeSwap: true)
    }

    override func supports(tokenIn: MarketKit.Token, tokenOut: MarketKit.Token) -> Bool {
        switch (tokenIn.blockchainType, tokenOut.blockchainType) {
        case (.ethereum, .ethereum): return true
        case (.binanceSmartChain, .binanceSmartChain): return true
        case (.polygon, .polygon): return true
        case (.safe4, .safe4): return true
        default: return false
        }
    }
}
