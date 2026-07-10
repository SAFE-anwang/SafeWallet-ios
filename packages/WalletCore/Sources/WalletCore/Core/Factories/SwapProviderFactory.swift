import OneInchKit
import UniswapKit

class SwapProviderFactory {
    static func provider(id: String) -> IMultiSwapProvider? {
        if id == OneInchMultiSwapProvider.id, let apiKey = AppConfig.oneInchApiKey {
            return OneInchMultiSwapProvider(kit: OneInchKit.Kit.instance(apiKey: apiKey))
        }

        if id == ThorChainMultiSwapProvider.id {
            return ThorChainMultiSwapProvider()
        }

        if id == MayaMultiSwapProvider.id {
            return MayaMultiSwapProvider()
        }

        if id == AllBridgeMultiSwapProvider.id {
            return AllBridgeMultiSwapProvider()
        }

        if id == JupiterMultiSwapProvider.id {
            return JupiterMultiSwapProvider()
        }

        if id == "uniswap", let kit = try? UniswapKit.Kit.instance() {
            return UniswapV2MultiSwapProvider(kit: kit)
        }

        if id == "uniswap_v3", let kit = try? UniswapKit.KitV3.instance(dexType: .uniswap) {
            return UniswapV3MultiSwapProvider(kit: kit)
        }

        if id == "pancake", let kit = try? UniswapKit.Kit.instance() {
            return PancakeV2MultiSwapProvider(kit: kit)
        }

        if id == "pancake_v3", let kit = try? UniswapKit.KitV3.instance(dexType: .pancakeSwap) {
            return PancakeV3MultiSwapProvider(kit: kit)
        }

        if id == "quickswap", let kit = try? UniswapKit.Kit.instance() {
            return QuickSwapMultiSwapProvider(kit: kit)
        }

        if id == "SafeSwap", let kit = try? UniswapKit.Kit.instance(isSafeSwap: true) {
            return SafeSwapMultiSwapProvider(kit: kit)
        }

        if let provider = USwapMultiSwapProvider.Provider(rawValue: id) {
            return USwapMultiSwapProvider(provider: provider)
        }

        return nil
    }

    static func providerName(id: String) -> String? {
        if let provider = USwapMultiSwapProvider.Provider(rawValue: id) {
            return provider.title
        }

        let names: [String: String] = [
            OneInchMultiSwapProvider.id: OneInchMultiSwapProvider.name,
            ThorChainMultiSwapProvider.id: ThorChainMultiSwapProvider.name,
            MayaMultiSwapProvider.id: MayaMultiSwapProvider.name,
            AllBridgeMultiSwapProvider.id: AllBridgeMultiSwapProvider.name,
            JupiterMultiSwapProvider.id: JupiterMultiSwapProvider.name,
            "uniswap": "Uniswap v.2",
            "uniswap_v3": "Uniswap v.3",
            "pancake": "PancakeSwap v.2",
            "pancake_v3": "PancakeSwap v.3",
            "quickswap": "QuickSwap",
            "SafeSwap": "SafeSwap",
        ]

        return names[id]
    }
}
