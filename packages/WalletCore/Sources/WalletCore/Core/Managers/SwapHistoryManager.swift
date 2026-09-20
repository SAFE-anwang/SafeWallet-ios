import Combine
import Foundation

public class SwapHistoryManager {
    private let accountManager: AccountManager
    private let storage: SwapStorage
    private var cancellables = Set<AnyCancellable>()
    private var syncTimer: AnyCancellable?
    private var isSyncing = false

    private let swapUpdateSubject = PassthroughSubject<Swap, Never>()

    // No work in init: the first sync is kicked by AppManager.didFinishLaunching, once the app
    // (registries, adapters, host-app context) is assembled.
    init(accountManager: AccountManager, storage: SwapStorage) {
        self.accountManager = accountManager
        self.storage = storage

        accountManager.activeAccountPublisher
            .sink { [weak self] _ in self?.sync() }
            .store(in: &cancellables)

        ChildWalletBridge.shared.activeChildWalletChangedPublisher
            .sink { [weak self] change in
                guard self?.accountManager.activeAccount?.id == change.parentAccountId else {
                    return
                }

                self?.sync()
            }
            .store(in: &cancellables)

        sync()
    }

    private func _sync() async throws {
        guard let account = accountManager.activeAccount else {
            return
        }

        let pendingSwaps = try storage.pendingSwaps(accountId: ChildWalletBridge.shared.contextAccountId(account: account))

        guard !pendingSwaps.isEmpty else {
            return
        }

        var hasStillPendingSwaps = false

        for swap in pendingSwaps {
            // mechanism-pending: there is no on-chain hash to track by yet; resolve() will supply it.
            // Swaps without a trackingHandle keep today's behaviour even with a nil txHash
            // (deposit-based providers track by providerSwapId alone)
            if Self.isAwaitingTxHash(swap) {
                hasStillPendingSwaps = true
                continue
            }

            guard let provider = SwapProviderFactory.provider(id: swap.providerId) else {
                // A local provider (for example SafeSwap) may be temporarily
                // unavailable while its kit is being assembled. Keep the record
                // pending so the next poll can retry instead of losing tracking.
                hasStillPendingSwaps = true
                continue
            }

            do {
                let updatedSwap = try await provider.track(swap: swap)
                try storage.save(swap: updatedSwap)
                swapUpdateSubject.send(updatedSwap)

                if updatedSwap.isPending {
                    hasStillPendingSwaps = true
                }
            } catch {
                print(error)
                hasStillPendingSwaps = true
            }
        }

        if hasStillPendingSwaps {
            scheduleTimer()
        }
    }

    private func scheduleTimer() {
        syncTimer?.cancel()
        syncTimer = Just(())
            .delay(for: .seconds(15), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.sync()
            }
    }
}

public extension SwapHistoryManager {
    var swapUpdatePublisher: AnyPublisher<Swap, Never> {
        swapUpdateSubject.eraseToAnyPublisher()
    }

    func pendingSwaps(account: Account) -> [Swap] {
        do {
            return try storage.pendingSwaps(accountId: ChildWalletBridge.shared.contextAccountId(account: account))
        } catch {
            return []
        }
    }

    func sync() {
        guard !isSyncing else {
            return
        }

        syncTimer?.cancel()
        syncTimer = nil
        isSyncing = true

        Task { [weak self] in
            do {
                try await self?._sync()
            } catch {
                print(error)
            }

            self?.isSyncing = false
        }
    }

    internal func lastSwap(accountId: String) -> Swap? {
        try? storage.lastSwap(accountId: accountId)
    }

    func lastSwap(account: Account) -> Swap? {
        lastSwap(accountId: ChildWalletBridge.shared.contextAccountId(account: account))
    }

    func swaps(accountId: String, from: Date? = nil, limit: Int) -> [Swap] {
        do {
            return try storage.swaps(accountId: accountId, from: from, limit: limit)
        } catch {
            return []
        }
    }

    func swaps(account: Account, from: Date? = nil, limit: Int) -> [Swap] {
        swaps(accountId: ChildWalletBridge.shared.contextAccountId(account: account), from: from, limit: limit)
    }

    func save(swap: Swap) {
        do {
            try storage.save(swap: swap)
            swapUpdateSubject.send(swap)
            sync()
        } catch {
            print(error)
        }
    }

    // mechanism-agnostic hook: attaches the on-chain txHash to the swap saved with
    // this trackingHandle and starts tracking it
    func resolve(trackingHandle: String, txHash: String) {
        do {
            guard try storage.setTxHash(txHash, trackingHandle: trackingHandle) else {
                return
            }

            sync()
        } catch {
            print(error)
        }
    }

    // mechanism-agnostic hook: the mechanism itself learned the swap failed (e.g. a reverted /
    // never-mined userOp) — no server tracking involved. Targeted update scoped to pending
    // statuses; a settled swap is never downgraded, a re-delivery is a no-op.
    func markFailed(trackingHandle: String) {
        do {
            guard try storage.markFailed(trackingHandle: trackingHandle) else {
                return
            }

            if let swap = try storage.swap(trackingHandle: trackingHandle) {
                swapUpdateSubject.send(swap)
            }
        } catch {
            print(error)
        }
    }

    internal static func isAwaitingTxHash(_ swap: Swap) -> Bool {
        swap.trackingHandle != nil && swap.txHash == nil
    }
}
