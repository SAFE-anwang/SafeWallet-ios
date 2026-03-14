import MarketKit
import UniswapKit

typealias LiquidityTickType = KitV3.LiquidityTickType

extension LiquidityAddViewModel {
    static func instance(token: MarketKit.Token? = nil) -> LiquidityAddViewModel {
        let storage = MultiSwapSettingStorage()
        var providers = [ILiquidityAddProvider]()

        if let kit = try? UniswapKit.Kit.instance() {
            providers.append(UniswapV2LiquidityAddProvider(kit: kit, storage: storage))
            providers.append(PancakeV2LiquidityAddProvider(kit: kit, storage: storage))
        }

        if let safeKit = try? UniswapKit.Kit.instance(isSafeSwap: true) {
            providers.append(SafeLiquidityAddProvider(kit: safeKit, storage: storage))
        }

        if let kit = try? UniswapKit.KitV3.instance(dexType: .pancakeSwap),
           let rpcSource = Core.shared.evmSyncSourceManager.httpSyncSource(blockchainType: .binanceSmartChain)?.rpcSource {
            providers.append(PancakeV3LiquidityAddProvider(kit: kit, storage: storage, rpcSource: rpcSource))
        }
        return LiquidityAddViewModel(providers: providers, token: token)
    }
}
