import Foundation
import RxRelay
import RxSwift

class Pool {
    private let provider: IPoolProvider
    private let disposeBag = DisposeBag()
    private let safeRefreshInterval: TimeInterval = 3.5

    private let invalidatedRelay = PublishRelay<Void>()
    private let itemsUpdatedRelay = PublishRelay<[TransactionItem]>()

    private(set) var items = [TransactionItem]()
    private var invalidated = false
    private var allLoaded = false
    private var safeInvalidationScheduled = false
    private var safeItemsUpdateScheduled = false
    private var safeSyncSettling = false
    private var safeSyncSettlementToken = 0
    private var pendingSafeUpdatedItems = [String: TransactionItem]()

    private let queue = DispatchQueue(label: "\(AppConfig.label).pool", qos: .userInitiated)

    init(provider: IPoolProvider) {
        self.provider = provider

        provider.recordsObservable()
            .observeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .subscribe(onNext: { [weak self] records in
                self?.handleUpdated(records: records)
            })
            .disposed(by: disposeBag)

        provider.lastBlockUpdatedObservable()
            .observeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .subscribe(onNext: { [weak self] in
                self?.handleUpdatedLastBlock()
            })
            .disposed(by: disposeBag)

        provider.syncingObservable
            .observeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .subscribe(onNext: { [weak self] _ in
                self?.handleSyncingChanged()
            })
            .disposed(by: disposeBag)
    }

    private var shouldCoalesceSafeInvalidation: Bool {
        provider.blockchainType == .safe && (provider.syncing || safeSyncSettling)
    }

    private var shouldCoalesceSafeItemUpdates: Bool {
        provider.blockchainType == .safe && (provider.syncing || safeSyncSettling)
    }

    private func emitInvalidation() {
        if shouldCoalesceSafeInvalidation {
            scheduleSafeInvalidation()
        } else {
            invalidatedRelay.accept(())
        }
    }

    private func scheduleSafeInvalidation() {
        guard !safeInvalidationScheduled else {
            return
        }

        safeInvalidationScheduled = true

        queue.asyncAfter(deadline: .now() + safeRefreshInterval) {
            self.safeInvalidationScheduled = false

            guard self.invalidated else {
                return
            }

            self.invalidatedRelay.accept(())
        }
    }

    private func emitItemsUpdated(_ items: [TransactionItem]) {
        guard !items.isEmpty else {
            return
        }

        if shouldCoalesceSafeItemUpdates {
            for item in items {
                pendingSafeUpdatedItems[item.record.uid] = item
            }

            scheduleSafeItemsUpdate()
        } else {
            flushPendingSafeItemsUpdatesIfNeeded()
            itemsUpdatedRelay.accept(items)
        }
    }

    private func scheduleSafeItemsUpdate() {
        guard !safeItemsUpdateScheduled else {
            return
        }

        safeItemsUpdateScheduled = true

        queue.asyncAfter(deadline: .now() + safeRefreshInterval) {
            self.flushPendingSafeItemsUpdatesIfNeeded()
        }
    }

    private func flushPendingSafeItemsUpdatesIfNeeded() {
        safeItemsUpdateScheduled = false

        guard !pendingSafeUpdatedItems.isEmpty else {
            return
        }

        let items = pendingSafeUpdatedItems.values.sorted()
        pendingSafeUpdatedItems.removeAll(keepingCapacity: true)
        itemsUpdatedRelay.accept(items)
    }

    private func handleSyncingChanged() {
        queue.async {
            guard self.provider.blockchainType == .safe else {
                guard !self.provider.syncing else {
                    return
                }

                self.flushPendingSafeItemsUpdatesIfNeeded()

                if self.invalidated {
                    self.invalidatedRelay.accept(())
                }
                return
            }

            self.safeSyncSettlementToken += 1
            let token = self.safeSyncSettlementToken

            guard !self.provider.syncing else {
                self.safeSyncSettling = false
                return
            }

            self.safeSyncSettling = true

            self.queue.asyncAfter(deadline: .now() + self.safeRefreshInterval) {
                guard token == self.safeSyncSettlementToken else {
                    return
                }

                self.safeSyncSettling = false

                guard !self.provider.syncing else {
                    return
                }

                self.flushPendingSafeItemsUpdatesIfNeeded()

                if self.invalidated {
                    self.invalidatedRelay.accept(())
                }
            }
        }
    }

    // new
    private func handleUpdated(records: [TransactionRecord]) {
        queue.async {
            guard !records.isEmpty else {
                return
            }

            var updatedItems = [TransactionItem]()
            var newRecords = [TransactionRecord]()
            let lastBlockInfo = self.provider.lastBlockInfo

            for record in records {
                if let index = self.items.firstIndex(where: { $0.record == record }) {
                    self.items[index].record = record
                    if self.items[index].status.isPendingOrProcessing {
                        let newStatus = record.status(lastBlockHeight: lastBlockInfo?.height)
                        if self.items[index].status != newStatus {
                            self.items[index].status = newStatus
                        }
                    }
                    updatedItems.append(self.items[index])
                } else {
                    newRecords.append(record)
                }
            }

            self.emitItemsUpdated(updatedItems)

            if !newRecords.isEmpty {
                self.invalidated = true
                self.emitInvalidation()
            }
        }
    }

    private func handleUpdatedLastBlock() {
        queue.async {
            let lastBlockInfo = self.provider.lastBlockInfo

//            print("Handle updated last block: \(lastBlockInfo?.height ?? -1)")

            var updatedItems = [TransactionItem]()

            for index in 0 ..< self.items.count {
                let item = self.items[index]
                var changed = false

                if item.status.isPendingOrProcessing {
                    let newStatus = item.record.status(lastBlockHeight: lastBlockInfo?.height)
                    if item.status != newStatus {
                        self.items[index].status = newStatus
                        changed = true
                    }
                }

                if let lockState = item.lockState, lockState.locked, let newLockState = item.record.lockState(lastBlockTimestamp: lastBlockInfo?.timestamp), !newLockState.locked {
                    self.items[index].lockState = newLockState
                    changed = true
                }

                if changed {
                    updatedItems.append(self.items[index])
                }
            }

            self.emitItemsUpdated(updatedItems)
        }
    }

    private func handleFetched(items: [TransactionItem], requestedCount: Int) {
        queue.async {
            self.items = items

            self.allLoaded = items.count < requestedCount
        }
    }

    private func transactionItems(records: [TransactionRecord]) -> [TransactionItem] {
        let lastBlockInfo = provider.lastBlockInfo

        return records.map { record in
            TransactionItem(
                record: record,
                status: record.status(lastBlockHeight: lastBlockInfo?.height),
                lockState: record.lockState(lastBlockTimestamp: lastBlockInfo?.timestamp)
            )
        }
    }
}

extension Pool {
    var invalidatedObservable: Observable<Void> {
        invalidatedRelay.asObservable()
    }

    var itemsUpdatedObservable: Observable<[TransactionItem]> {
        itemsUpdatedRelay.asObservable()
    }

    var syncing: Bool {
        provider.syncing
    }

    var syncingObservable: Observable<Bool> {
        provider.syncingObservable
    }

    func itemsSingle(count: Int) -> Single<[TransactionItem]> {
        queue.sync {
//            print("Pool: single for \(count)\(invalidated ? " (INVALIDATED)" : "")")

            if invalidated {
                invalidated = false

                return provider.recordsSingle(from: nil, limit: count)
                    .map { [weak self] records in
                        self?.transactionItems(records: records) ?? []
                    }
                    .do(onSuccess: { [weak self] items in
                        self?.handleFetched(items: items, requestedCount: count)
                    })
            } else if allLoaded {
                return Single.just(items)
            } else {
                let items = items

                if items.count >= count {
                    return Single.just(items)
                }

                let requiredCount = count - items.count
                let lastItem = items.last

                return provider.recordsSingle(from: lastItem?.record, limit: requiredCount)
                    .map { [weak self] records in
                        self?.transactionItems(records: records) ?? []
                    }
                    .map {
                        items + $0
                    }
                    .do(onSuccess: { [weak self] items in
                        self?.handleFetched(items: items, requestedCount: count)
                    })
            }
        }
    }
}
