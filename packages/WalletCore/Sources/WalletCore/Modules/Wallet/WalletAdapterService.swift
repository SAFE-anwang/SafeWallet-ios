import Foundation
import RxRelay
import RxSwift

protocol IWalletAdapterServiceDelegate: AnyObject {
    func didPrepareAdapters()
    func didUpdate(balanceData: BalanceData, wallet: Wallet)
    func didUpdate(state: AdapterState, wallet: Wallet)
    func didUpdate(caution: CautionNew?, wallet: Wallet)
}

class WalletAdapterService {
    weak var delegate: IWalletAdapterServiceDelegate?

    private let account: Account
    private let adapterManager: AdapterManager
    private let disposeBag = DisposeBag()
    private var adaptersDisposeBag = DisposeBag()

    private var adapterMap: [Wallet: IBalanceAdapter] = [:]
    private var hasPreparedAdapters = false
    private var subscriptionGeneration = 0
    private var subscribedChildWalletId: String?
    private let generationLock = NSLock()

    private let queue = DispatchQueue(label: "\(AppConfig.label).wallet-adapter-service", qos: .userInitiated)

    init(account: Account, adapterManager: AdapterManager) {
        self.account = account
        self.adapterManager = adapterManager

        adapterManager.adapterDataReadyObservable
            .observeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .subscribe(onNext: { [weak self] adapterData in
                guard let self, self.matchesCurrentContext(adapterData) else {
                    return
                }
                self.handleAdaptersReady(adapterMap: adapterData.adapterMap, childWalletId: adapterData.childWalletId)
            })
            .disposed(by: disposeBag)

        let adapterData = adapterManager.adapterData
        if matchesCurrentContext(adapterData) {
            adapterMap = adapterData.adapterMap.compactMapValues { $0 as? IBalanceAdapter }
            subscribedChildWalletId = adapterData.childWalletId
            hasPreparedAdapters = true
        }
        subscribeToAdapters()
    }

    private func matchesCurrentContext(_ adapterData: AdapterManager.AdapterData) -> Bool {
        guard adapterData.account?.id == account.id else {
            return false
        }

        let activeWalletData = Core.shared.walletManager.activeWalletData
        return activeWalletData.account?.id == account.id
            && activeWalletData.childWalletId == adapterData.childWalletId
            && Set(adapterData.adapterMap.keys).isSubset(of: Set(activeWalletData.wallets))
    }

    private func handleAdaptersReady(adapterMap: [Wallet: IAdapter], childWalletId: String?) {
        queue.async {
            let currentAdapterData = self.adapterManager.adapterData
            guard currentAdapterData.account?.id == self.account.id,
                  currentAdapterData.childWalletId == childWalletId,
                  self.matchesCurrentContext(currentAdapterData)
            else {
                return
            }

            self.adapterMap = adapterMap.compactMapValues { $0 as? IBalanceAdapter }
            self.hasPreparedAdapters = true
            self.generationLock.withLock {
                self.subscribedChildWalletId = childWalletId
            }
            self.subscribeToAdapters()
            self.delegate?.didPrepareAdapters()
        }
    }

    private func subscribeToAdapters() {
        adaptersDisposeBag = DisposeBag()
        let generation = generationLock.withLock {
            subscriptionGeneration += 1
            return subscriptionGeneration
        }

        for (wallet, adapter) in adapterMap {
            subscribe(adaptersDisposeBag, adapter.balanceDataUpdatedObservable) { [weak self] in
                guard let self, self.isCurrentGeneration(generation) else { return }
                self.delegate?.didUpdate(balanceData: $0, wallet: wallet)
            }

            subscribe(adaptersDisposeBag, adapter.balanceStateUpdatedObservable) { [weak self] in
                guard let self, self.isCurrentGeneration(generation) else { return }
                self.delegate?.didUpdate(state: $0, wallet: wallet)
            }

            subscribe(adaptersDisposeBag, adapter.cautionUpdatedObservable) { [weak self] in
                guard let self, self.isCurrentGeneration(generation) else { return }
                self.delegate?.didUpdate(caution: $0, wallet: wallet)
            }
        }
    }

    private func isCurrentGeneration(_ generation: Int) -> Bool {
        let isCurrent = generationLock.withLock { subscriptionGeneration == generation }
        guard isCurrent else { return false }

        let activeWalletData = Core.shared.walletManager.activeWalletData
        return activeWalletData.account?.id == account.id
            && generationLock.withLock { activeWalletData.childWalletId == subscribedChildWalletId }
    }
}

extension WalletAdapterService {
    func isMainNet(wallet: Wallet) -> Bool? {
        queue.sync { adapterMap[wallet]?.isMainNet }
    }

    func balanceData(wallet: Wallet) -> BalanceData? {
        queue.sync { adapterMap[wallet]?.balanceData }
    }

    func balanceCaution(wallet: Wallet) -> CautionNew? {
        queue.sync { adapterMap[wallet]?.caution }
    }

    func state(wallet: Wallet) -> AdapterState? {
        queue.sync {
            if let adapter = adapterMap[wallet] {
                return adapter.balanceState
            }
            return hasPreparedAdapters ? .notSynced(error: "Wallet adapter unavailable") : nil
        }
    }

    func refresh() {
        adapterManager.refresh()
    }
}
