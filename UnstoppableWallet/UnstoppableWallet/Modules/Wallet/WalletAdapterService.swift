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
    private var lastBalanceDataMap: [Wallet: BalanceData] = [:]
    private var lastStateMap: [Wallet: AdapterState] = [:]
    private var lastCautionMap: [Wallet: CautionNew?] = [:]

    private let queue = DispatchQueue(label: "\(AppConfig.label).wallet-adapter-service", qos: .userInitiated)

    init(account: Account, adapterManager: AdapterManager) {
        self.account = account
        self.adapterManager = adapterManager

        adapterManager.adapterDataReadyObservable
            .observeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .subscribe(onNext: { [weak self] adapterData in
                guard adapterData.account == self?.account else {
                    return
                }
                self?.handleAdaptersReady(adapterMap: adapterData.adapterMap)
            })
            .disposed(by: disposeBag)

        let adapterData = adapterManager.adapterData
        if adapterData.account == account {
            adapterMap = adapterData.adapterMap.compactMapValues { $0 as? IBalanceAdapter }
        }
        subscribeToAdapters()
    }

    private func handleAdaptersReady(adapterMap: [Wallet: IAdapter]) {
        queue.async {
            self.adapterMap = adapterMap.compactMapValues { $0 as? IBalanceAdapter }
            self.lastBalanceDataMap = [:]
            self.lastStateMap = [:]
            self.lastCautionMap = [:]
            self.subscribeToAdapters()
            self.delegate?.didPrepareAdapters()
        }
    }

    private func subscribeToAdapters() {
        adaptersDisposeBag = DisposeBag()

        for (wallet, adapter) in adapterMap {
            subscribe(adaptersDisposeBag, adapter.balanceDataUpdatedObservable) { [weak self] in
                self?.handleUpdated(balanceData: $0, wallet: wallet)
            }

            subscribe(adaptersDisposeBag, adapter.balanceStateUpdatedObservable) { [weak self] in
                self?.handleUpdated(state: $0, wallet: wallet)
            }

            subscribe(adaptersDisposeBag, adapter.cautionUpdatedObservable) { [weak self] in
                self?.handleUpdated(caution: $0, wallet: wallet)
            }
        }
    }

    private func handleUpdated(balanceData: BalanceData, wallet: Wallet) {
        queue.async {
            if self.lastBalanceDataMap[wallet] == balanceData {
                return
            }

            self.lastBalanceDataMap[wallet] = balanceData
            self.delegate?.didUpdate(balanceData: balanceData, wallet: wallet)
        }
    }

    private func handleUpdated(state: AdapterState, wallet: Wallet) {
        queue.async {
            if self.lastStateMap[wallet] == state {
                return
            }

            self.lastStateMap[wallet] = state
            self.delegate?.didUpdate(state: state, wallet: wallet)
        }
    }

    private func handleUpdated(caution: CautionNew?, wallet: Wallet) {
        queue.async {
            if self.lastCautionMap[wallet] == caution {
                return
            }

            self.lastCautionMap[wallet] = caution
            self.delegate?.didUpdate(caution: caution, wallet: wallet)
        }
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
        queue.sync { adapterMap[wallet]?.balanceState }
    }

    func refresh() {
        adapterManager.refresh()
    }
}
