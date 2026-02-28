import MarketKit
import UniswapKit
import EvmKit

class SafeLiquidityAddProvider: BaseUniswapV2LiquidityAddProvider {
    override var id: String {
        "safeswap"
    }

    override var name: String {
        "SafeSwap"
    }

    override var icon: String {
        "safe-anwang_trx_32"
    }
    
    override func spenderAddress(chain: Chain) throws -> Address {
        try super.kit.routerAddress(chain: chain, isSafeSwap: true)
    }

    override func supports(token0 tokenIn: MarketKit.Token, token1 tokenOut: MarketKit.Token) -> Bool {
        switch (tokenIn.blockchainType, tokenOut.blockchainType) {
        case (.safe4, .safe4): return true
        default: return false
        }
    }
}
