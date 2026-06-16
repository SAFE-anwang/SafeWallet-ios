import Foundation
import MarketKit
import RxRelay
import RxSwift

protocol IPoolProvider {
    var blockchainType: BlockchainType { get }
    var syncing: Bool { get }
    var syncingObservable: Observable<Bool> { get }
    var lastBlockInfo: LastBlockInfo? { get }
    func recordsSingle(from: TransactionRecord?, limit: Int) -> Single<[TransactionRecord]>
    func recordsObservable() -> Observable<[TransactionRecord]>
    func lastBlockUpdatedObservable() -> Observable<Void>
}

class PoolProvider {
    private let adapter: ITransactionsAdapter
    private let source: PoolSource
    private let disposeBag = DisposeBag()
    private let safeSyncScheduler = SerialDispatchQueueScheduler(qos: .userInitiated, internalSerialQueueName: "\(AppConfig.label).pool-provider.safe-sync")

    private let syncingRelay = PublishRelay<Bool>()
    private(set) var syncing = false {
        didSet {
            if oldValue != syncing {
                syncingRelay.accept(syncing)
            }
        }
    }

    init(adapter: ITransactionsAdapter, source: PoolSource) {
        self.adapter = adapter
        self.source = source

        adapter.syncingObservable
            .observeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .subscribe(onNext: { [weak self] in
                self?.syncing = adapter.syncing
            })
            .disposed(by: disposeBag)

        syncing = adapter.syncing
    }

    private var shouldThrottleSafeSyncEvents: Bool {
        source.blockchainType == .safe
    }

    private var safeSyncStateObservable: Observable<Bool> {
        syncingRelay.asObservable()
            .startWith(syncing)
            .distinctUntilChanged()
    }
}

extension PoolProvider: IPoolProvider {
    var blockchainType: BlockchainType {
        source.blockchainType
    }

    var syncingObservable: Observable<Bool> {
        syncingRelay.asObservable()
    }

    var lastBlockInfo: LastBlockInfo? {
        adapter.lastBlockInfo
    }

    func recordsSingle(from: TransactionRecord?, limit: Int) -> Single<[TransactionRecord]> {
        adapter.transactionsSingle(paginationData: from?.paginationRaw, token: source.token, filter: source.filter, address: source.address, limit: limit)
    }

    func recordsObservable() -> Observable<[TransactionRecord]> {
        guard shouldThrottleSafeSyncEvents else {
            return adapter.transactionsObservable(token: source.token, filter: source.filter, address: source.address)
        }

        return safeSyncStateObservable
            .flatMapLatest { [weak self] syncing -> Observable<[TransactionRecord]> in
                guard let self else {
                    return .empty()
                }

                let observable = self.adapter.transactionsObservable(token: self.source.token, filter: self.source.filter, address: self.source.address)
                if syncing {
                    return observable.throttle(.seconds(3), latest: true, scheduler: self.safeSyncScheduler)
                }
                return observable
            }
    }

    func lastBlockUpdatedObservable() -> Observable<Void> {
        guard shouldThrottleSafeSyncEvents else {
            return adapter.lastBlockUpdatedObservable
        }

        return safeSyncStateObservable
            .flatMapLatest { [weak self] syncing -> Observable<Void> in
                guard let self else {
                    return .empty()
                }

                let observable = self.adapter.lastBlockUpdatedObservable
                if syncing {
                    return observable.throttle(.seconds(4), latest: true, scheduler: self.safeSyncScheduler)
                }
                return observable
            }
    }
}
