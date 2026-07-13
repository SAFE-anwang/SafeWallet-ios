import Combine
import MarketKit

@MainActor
final class Safe4NetworkSwitchService: ObservableObject {
    private let localStorage: LocalStorage
    private let evmBlockchainManager: EvmBlockchainManager
    private let adapterManager: AdapterManager
    private let marketKit: MarketKit.Kit
    private let userDefaultsStorage: UserDefaultsStorage

    @Published private(set) var isTestNet: Bool
    @Published private(set) var isSwitching = false

    init(localStorage: LocalStorage, evmBlockchainManager: EvmBlockchainManager, adapterManager: AdapterManager, marketKit: MarketKit.Kit, userDefaultsStorage: UserDefaultsStorage) {
        self.localStorage = localStorage
        self.evmBlockchainManager = evmBlockchainManager
        self.adapterManager = adapterManager
        self.marketKit = marketKit
        self.userDefaultsStorage = userDefaultsStorage
        isTestNet = localStorage.isSafe4TestNet
    }

    static func live() -> Safe4NetworkSwitchService {
        Safe4NetworkSwitchService(
            localStorage: Core.shared.localStorage,
            evmBlockchainManager: Core.shared.evmBlockchainManager,
            adapterManager: Core.shared.adapterManager,
            marketKit: Core.shared.marketKit,
            userDefaultsStorage: Core.shared.userDefaultsStorage
        )
    }

    func set(testNet enabled: Bool) {
        guard !isSwitching else {
            isTestNet = localStorage.isSafe4TestNet
            return
        }

        guard enabled != localStorage.isSafe4TestNet else {
            isTestNet = enabled
            return
        }

        isSwitching = true
        defer { isSwitching = false }

        adapterManager.cancelSafe4SyncManager()
        localStorage.isSafe4TestNet = enabled
        AppConfig.isSafe4TestNet = enabled
        MarketKit.isSafe4TestNet = enabled
        Safe4Network.restoreDeployContractsCache(userDefaultsStorage: userDefaultsStorage, chainId: Safe4Network.chainId(testNet: enabled))
        isTestNet = enabled

        marketKit.sync()
        evmBlockchainManager.resyncSafe4()
        adapterManager.recreateAdapter(blockchainType: .safe4)
    }
}
