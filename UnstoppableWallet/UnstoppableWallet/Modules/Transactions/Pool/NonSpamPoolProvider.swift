import Foundation
import RxRelay
import RxSwift

class NonSpamPoolProvider {
    private let poolProvider: IPoolProvider
    private let scamFilterEnabled: Bool
    private let safe4IncomeEnabled: Bool
    private let safe4NodestatusEnabled: Bool
    init(poolProvider: IPoolProvider, scamFilterEnabled: Bool,safe4IncomeEnabled: Bool, safe4NodestatusEnabled: Bool) {
        self.poolProvider = poolProvider
        self.scamFilterEnabled = scamFilterEnabled
        self.safe4IncomeEnabled = safe4IncomeEnabled
        self.safe4NodestatusEnabled = safe4NodestatusEnabled
    }

    private func single(from: TransactionRecord?, limit: Int, transactions: [TransactionRecord] = []) -> Single<[TransactionRecord]> {
        let extendedLimit = limit * 2
//        let extendedLimit = limit

        return poolProvider.recordsSingle(from: from, limit: extendedLimit)
            .flatMap { [weak self] newTransactions in
                let allTransactions = transactions + newTransactions
                var nonSpamTransactions = allTransactions
                if self?.scamFilterEnabled == true {
                    nonSpamTransactions = nonSpamTransactions.filter { !$0.spam }
                }
                
                if self?.safe4IncomeEnabled == true {
                    nonSpamTransactions = nonSpamTransactions.filter { !$0.isSafe4Incoming }
                }
                
                if self?.safe4NodestatusEnabled == true {
                    nonSpamTransactions = nonSpamTransactions.filter { !$0.isNodestatus }
                }

                if nonSpamTransactions.count >= limit || newTransactions.count < extendedLimit {
                    return Single.just(Array(nonSpamTransactions.prefix(limit)))
                } else {
                    return self?.single(from: allTransactions.last, limit: limit, transactions: allTransactions) ?? Single.just([])
                }
            }
    }
}

extension NonSpamPoolProvider: IPoolProvider {
    var syncing: Bool {
        poolProvider.syncing
    }

    var syncingObservable: Observable<Bool> {
        poolProvider.syncingObservable
    }

    var lastBlockInfo: LastBlockInfo? {
        poolProvider.lastBlockInfo
    }

    func recordsSingle(from: TransactionRecord?, limit: Int) -> Single<[TransactionRecord]> {
        single(from: from, limit: limit)
    }

    func recordsObservable() -> Observable<[TransactionRecord]> {
        poolProvider.recordsObservable()
            .map { [weak self] transactions in
                var nonSpamTransactions = transactions
                if self?.scamFilterEnabled == true {
                    nonSpamTransactions = nonSpamTransactions.filter {!$0.spam}
                }
//                
//                if self?.safe4IncomeEnabled == true {
//                    nonSpamTransactions = nonSpamTransactions.filter { !$0.isSafe4Incoming }
//                }
//                
//                if self?.safe4NodestatusEnabled == true {
//                    nonSpamTransactions = nonSpamTransactions.filter { !$0.isNodestatus }
//                }
                return nonSpamTransactions
            }
    }

    func lastBlockUpdatedObservable() -> Observable<Void> {
        poolProvider.lastBlockUpdatedObservable()
    }
}
