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
    @Published private(set) var switchError: String?

    private var switchTask: Task<Void, Never>?
    private var requestedTestNet: Bool?
    private var retryRequested = false

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
        switchError = nil
        requestedTestNet = enabled
        if enabled == localStorage.isSafe4TestNet {
            retryRequested = true
        }
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
            let shouldRetry = retryRequested
            retryRequested = false

            guard enabled != localStorage.isSafe4TestNet || shouldRetry else {
                isTestNet = enabled
                continue
            }

            do {
                try await apply(testNet: enabled)
            } catch {
                retryRequested = false
                isTestNet = localStorage.isSafe4TestNet
                switchError = error.localizedDescription
            }
        }
    }

    private func apply(testNet enabled: Bool) async throws {
        let previousChainId = Safe4Network.currentChainId
        await adapterManager.cancelSafe4SyncManager()
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
        try await ensureSafe4Adapters(chainId: chainId)
        NotificationCenter.default.post(
            name: .safe4NetworkDidSwitch,
            object: nil,
            userInfo: ["chainId": chainId]
        )
    }

    private func ensureSafe4Adapters(chainId: Int) async throws {
        guard Safe4Network.isCurrent(chainId: chainId) else {
            throw Safe4NetworkError.staleContext(expected: chainId, current: Safe4Network.currentChainId)
        }

        for _ in 0 ..< 2 {
            let wallets = Core.shared.walletManager.activeWallets.filter { $0.token.blockchain.type == .safe4 }
            guard !wallets.isEmpty else { return }

            let isReady = wallets.allSatisfy { wallet in
                guard let adapter = adapterManager.adapter(for: wallet) as? BaseEvmAdapter else { return false }
                return adapter.evmKit.chain.id == chainId
            }
            if isReady { return }

            await adapterManager.initMissingAdaptersAndWait()
        }

        let missingCount = Core.shared.walletManager.activeWallets.filter { wallet in
            guard wallet.token.blockchain.type == .safe4 else { return false }
            guard let adapter = adapterManager.adapter(for: wallet) as? BaseEvmAdapter else { return true }
            return adapter.evmKit.chain.id != chainId
        }.count

        if missingCount > 0 {
            throw Safe4NetworkError.adapterUnavailable(chainId: chainId, count: missingCount)
        }
    }
}
