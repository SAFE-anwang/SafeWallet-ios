import Combine
import Foundation
import MarketKit

@MainActor
final class Safe4NetworkSwitchService: ObservableObject {
    private let localStorage: LocalStorage
    private let evmBlockchainManager: EvmBlockchainManager
    private let adapterManager: AdapterManager
    private let marketKit: MarketKit.Kit
    private let userDefaultsStorage: UserDefaultsStorage
    private let src20ProjectionCoordinator: Safe4SRC20ProjectionCoordinator

    @Published private(set) var isTestNet: Bool
    @Published private(set) var isSwitching = false

    private var switchTask: Task<Void, Never>?
    private var requestedTestNet: Bool?

    init(localStorage: LocalStorage, evmBlockchainManager: EvmBlockchainManager, adapterManager: AdapterManager, marketKit: MarketKit.Kit, userDefaultsStorage: UserDefaultsStorage, src20ProjectionCoordinator: Safe4SRC20ProjectionCoordinator) {
        self.localStorage = localStorage
        self.evmBlockchainManager = evmBlockchainManager
        self.adapterManager = adapterManager
        self.marketKit = marketKit
        self.userDefaultsStorage = userDefaultsStorage
        self.src20ProjectionCoordinator = src20ProjectionCoordinator
        isTestNet = localStorage.isSafe4TestNet
    }

    static func live() -> Safe4NetworkSwitchService {
        Safe4NetworkSwitchService(
            localStorage: Core.shared.localStorage,
            evmBlockchainManager: Core.shared.evmBlockchainManager,
            adapterManager: Core.shared.adapterManager,
            marketKit: Core.shared.marketKit,
            userDefaultsStorage: Core.shared.userDefaultsStorage,
            src20ProjectionCoordinator: Core.shared.safe4SRC20ProjectionCoordinator
        )
    }

    func set(testNet enabled: Bool) {
        requestedTestNet = enabled
        isTestNet = enabled

        guard switchTask == nil else {
            return
        }

        switchTask = Task { [weak self] in
            await self?.runPendingSwitches()
        }
    }

    private func runPendingSwitches() async {
        isSwitching = true
        defer {
            isSwitching = false
            switchTask = nil
            isTestNet = localStorage.isSafe4TestNet
        }

        while let enabled = requestedTestNet {
            requestedTestNet = nil

            guard enabled != localStorage.isSafe4TestNet else {
                isTestNet = enabled
                continue
            }

            await apply(testNet: enabled)
        }
    }

    private func apply(testNet enabled: Bool) async {
        let previousChainId = Safe4Network.currentChainId
        adapterManager.cancelSafe4SyncManager()
        src20ProjectionCoordinator.prepareSwitch(from: previousChainId)
        localStorage.isSafe4TestNet = enabled
        AppConfig.isSafe4TestNet = enabled
        MarketKit.isSafe4TestNet = enabled
        let chainId = Safe4Network.chainId(testNet: enabled)
        DAppChainIdStorage.storeSafe4ChainId(
            chainId,
            userDefaultsStorage: userDefaultsStorage
        )
        Safe4Network.restoreDeployContractsCache(userDefaultsStorage: userDefaultsStorage, chainId: chainId)
        isTestNet = enabled

        marketKit.sync()
        evmBlockchainManager.resyncSafe4()
        await src20ProjectionCoordinator.projectAndWait(
            chainId: chainId,
            replacing: previousChainId
        )
        await adapterManager.recreateAdapterAndWait(blockchainType: .safe4)
        NotificationCenter.default.post(
            name: .safe4NetworkDidSwitch,
            object: nil,
            userInfo: ["chainId": chainId]
        )
    }
}
