import Combine
import MarketKit

final class Safe4NetworkSwitchService: ObservableObject {
    private let localStorage: LocalStorage
    private let evmBlockchainManager: EvmBlockchainManager
    private let adapterManager: AdapterManager
    private let marketKit: MarketKit.Kit

    @Published private(set) var isTestNet: Bool

    init(localStorage: LocalStorage, evmBlockchainManager: EvmBlockchainManager, adapterManager: AdapterManager, marketKit: MarketKit.Kit) {
        self.localStorage = localStorage
        self.evmBlockchainManager = evmBlockchainManager
        self.adapterManager = adapterManager
        self.marketKit = marketKit
        isTestNet = localStorage.isSafe4TestNet
    }

    static func live() -> Safe4NetworkSwitchService {
        Safe4NetworkSwitchService(
            localStorage: Core.shared.localStorage,
            evmBlockchainManager: Core.shared.evmBlockchainManager,
            adapterManager: Core.shared.adapterManager,
            marketKit: Core.shared.marketKit
        )
    }

    func set(testNet enabled: Bool) {
        guard enabled != localStorage.isSafe4TestNet else {
            isTestNet = enabled
            return
        }

        localStorage.isSafe4TestNet = enabled
        AppConfig.isSafe4TestNet = enabled
        MarketKit.isSafe4TestNet = enabled
        isTestNet = enabled

        marketKit.sync()
        evmBlockchainManager.resyncSafe4()
        adapterManager.recreateAdapter(blockchainType: .safe4)
    }
}
