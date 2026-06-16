import Combine
import Foundation
import RxSwift

class BitcoinWalletTokenViewModel: ObservableObject {
    private let balanceHiddenManager = Core.shared.balanceHiddenManager
    private let adapter: BitcoinBaseAdapter
    private let disposeBag = DisposeBag()
    private let safeBalanceScheduler = SerialDispatchQueueScheduler(qos: .userInitiated, internalSerialQueueName: "\(AppConfig.label).bitcoin-wallet-token.safe-balance")
    private let safeBalanceRefreshInterval: RxTimeInterval = .seconds(3)
    private let safePostSyncBalanceRefreshInterval: RxTimeInterval = .seconds(2)

    @Published var bitcoinBalanceData: BitcoinBaseAdapter.BitcoinBalanceData
    @Published var balanceHidden: Bool

    init(adapter: BitcoinBaseAdapter) {
        self.adapter = adapter
        bitcoinBalanceData = adapter.bitcoinBalanceData
        balanceHidden = balanceHiddenManager.balanceHidden

        let stateObservable = adapter.balanceStateUpdatedObservable
            .map(\.syncing)
            .startWith(adapter.balanceState.syncing)
            .distinctUntilChanged()

        let balanceObservable = stateObservable
            .flatMapLatest { [weak self] syncing -> Observable<BitcoinBaseAdapter.BitcoinBalanceData> in
                guard let self else {
                    return .empty()
                }

                if self.shouldThrottleSafeBalanceUpdates(syncing: syncing) {
                    return self.adapter.bitcoinBalanceDataObservable
                        .throttle(self.safeBalanceRefreshInterval, latest: true, scheduler: self.safeBalanceScheduler)
                }
                return self.adapter.bitcoinBalanceDataObservable
            }

        let syncCompletionObservable = stateObservable
            .filter { [weak self] syncing in
                guard let self else {
                    return false
                }
                return self.adapter.token.blockchainType == .safe && !syncing
            }
            .flatMapLatest { [weak self] _ -> Observable<BitcoinBaseAdapter.BitcoinBalanceData> in
                guard let self else {
                    return .empty()
                }

                return Observable.just(self.adapter.bitcoinBalanceData)
                    .delay(self.safePostSyncBalanceRefreshInterval, scheduler: self.safeBalanceScheduler)
            }

        Observable.merge(balanceObservable, syncCompletionObservable)
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { [weak self] in self?.bitcoinBalanceData = $0 })
            .disposed(by: disposeBag)

        balanceHiddenManager.balanceHiddenObservable
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { [weak self] in
                self?.balanceHidden = $0
            })
            .disposed(by: disposeBag)
    }

    private func shouldThrottleSafeBalanceUpdates(syncing: Bool) -> Bool {
        adapter.token.blockchainType == .safe && syncing
    }
}
