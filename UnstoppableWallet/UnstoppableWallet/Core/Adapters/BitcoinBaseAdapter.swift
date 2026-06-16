import BitcoinCore
import Foundation
import HdWalletKit
import Hodler
import HsToolKit
import MarketKit
import RxSwift

class BitcoinBaseAdapter {
    static let confirmationsThreshold = 1 // Number of confirmations for coins in transaction to be available for spending
    static let txStatusConfirmationsThreshold = 3 // Number of confirmations for transaction status displayed
    private let abstractKit: AbstractKit

    var coinRate: Decimal { 100_000_000 } // pow(10, 8)

    private let bitcoinBalanceDataSubject = PublishSubject<BitcoinBalanceData>()

    // Cache the latest BitcoinBalanceData on the main thread so that the
    // IBalanceAdapter.balanceData getter (read by SwiftUI on every render)
    // never has to call `abstractKit.balance` — that getter iterates every
    // UTXO in UnspentOutputProvider and costs several seconds on a Safe3
    // wallet with thousands of UTXOs. Updates land here in balanceUpdated,
    // which is already debounced via `throttleSyncEvents`.
    private var cachedBitcoinBalanceData = BitcoinBalanceData(
        available: 0,
        locked: 0,
        notRelayed: 0
    )

    private let lastBlockUpdatedSubject = PublishSubject<Void>()
    private let balanceStateSubject = PublishSubject<AdapterState>()
    private let syncMode: BitcoinCore.SyncMode
    let transactionRecordsSubject = PublishSubject<[BitcoinTransactionRecord]>()
    private let syncEventsQueue = DispatchQueue(label: "\(AppConfig.label).bitcoin-base-adapter.sync-events", qos: .utility)
    private let transactionsConversionQueue = DispatchQueue(label: "\(AppConfig.label).bitcoin-base-adapter.transactions", qos: .userInitiated)

    // Throttle sync events to reduce main-thread pressure (opt-in for Safe3).
    // Instead of dropping events that arrive inside the throttle window, we keep
    // the latest event and flush it on a debounce timer. Terminal kit states
    // (.synced / .notSynced) bypass the throttle entirely.
    var throttleSyncEvents: Bool = false
    var syncEventThrottleInterval: TimeInterval {
        throttleSyncEvents ? 1.0 : 0
    }
    var transactionUpdateThrottleInterval: TimeInterval {
        throttleSyncEvents ? 1.0 : 0.2
    }

    private var pendingBalance: BalanceInfo?
    private var balanceFlushScheduled = false

    private var pendingLastBlockInfo: BlockInfo?
    private var lastBlockInfoFlushScheduled = false

    private var pendingKitState: BitcoinCore.KitState?
    private var kitStateFlushScheduled = false

    // transactionsUpdated is the heaviest of the delegate callbacks — it
    // converts every TransactionInfo to a BitcoinTransactionRecord on the
    // calling thread, which for a 1k-tx batch is ~10s of main-thread work.
    // Always throttle/merge this one, independent of `throttleSyncEvents`
    // (which is just for balance/lastBlock/kitState).
    private var pendingTxInserted: [TransactionInfo] = []
    private var pendingTxUpdated: [TransactionInfo] = []
    private var txFlushScheduled = false

    private(set) var balanceState: AdapterState {
        didSet {
            balanceStateSubject.onNext(balanceState)
            syncing = balanceState.syncing
        }
    }

    private(set) var syncing: Bool = true

    let token: Token
    private let transactionSource: TransactionSource

    init(abstractKit: AbstractKit, wallet: Wallet, syncMode: BitcoinCore.SyncMode) {
        self.abstractKit = abstractKit
        token = wallet.token
        transactionSource = wallet.transactionSource
        self.syncMode = syncMode

        balanceState = .notSynced(error: AppError.unknownError.localizedDescription)
        cachedBitcoinBalanceData = bitcoinBalanceData(balanceInfo: abstractKit.balance)
    }

    func transactionRecord(fromTransaction transaction: TransactionInfo) -> BitcoinTransactionRecord {
        var lockInfo: TransactionLockInfo?
        var anyNotMineFromAddress: String?
        var anyNotMineToAddress: String?

        for input in transaction.inputs {
            if anyNotMineFromAddress == nil, let address = input.address {
                anyNotMineFromAddress = address
            }
        }

        var memo: String? = nil
        for output in transaction.outputs {
            // get last memo (we use last output for memo op_return)
            if output.memo != nil {
                memo = output.memo
            }

            guard output.value > 0 else {
                continue
            }
            
            if let unlockedHeight = output.unlockedHeight, unlockedHeight > 0, let hodlerOutputData = output.pluginData as? HodlerOutputData {
                let approxUnlockTime = (abstractKit.lastBlockInfo?.timestamp ?? 0) + ((unlockedHeight - (abstractKit.lastBlockInfo?.height ?? 0))  * 30 )
                lockInfo = TransactionLockInfo(
                        lockedUntil: Date(timeIntervalSince1970: Double(approxUnlockTime)),
                        originalAddress: output.address ?? "__", 
                        lockTimeInterval: hodlerOutputData.lockTimeInterval,
                        unlockedHeight: unlockedHeight
                        )
                
            }else if let pluginId = output.pluginId, pluginId == HodlerPlugin.id,
               let hodlerOutputData = output.pluginData as? HodlerOutputData,
               let approximateUnlockTime = hodlerOutputData.approximateUnlockTime {

                lockInfo = TransactionLockInfo(
                    lockedUntil: Date(timeIntervalSince1970: Double(approximateUnlockTime)),
                    originalAddress: hodlerOutputData.addressString,
                    lockTimeInterval: hodlerOutputData.lockTimeInterval,
                    unlockedHeight: nil
                )
            }

            if anyNotMineToAddress == nil, let address = output.address, !output.mine {
                anyNotMineToAddress = address
            }
        }

        switch transaction.type {
        case .incoming:
            return BitcoinIncomingTransactionRecord(
                token: token,
                source: transactionSource,
                uid: transaction.uid,
                transactionHash: transaction.transactionHash,
                transactionIndex: transaction.transactionIndex,
                blockHeight: transaction.blockHeight,
                confirmationsThreshold: Self.txStatusConfirmationsThreshold,
                date: Date(timeIntervalSince1970: Double(transaction.timestamp)),
                fee: transaction.fee.map { Decimal($0) / coinRate },
                failed: transaction.status == .invalid,
                lockInfo: lockInfo,
                conflictingHash: transaction.conflictingHash,
                showRawTransaction: transaction.status == .new || transaction.status == .invalid,
                amount: Decimal(transaction.amount) / coinRate,
                from: anyNotMineFromAddress,
                memo: memo
            )
        case .outgoing:
            return BitcoinOutgoingTransactionRecord(
                token: token,
                source: transactionSource,
                uid: transaction.uid,
                transactionHash: transaction.transactionHash,
                transactionIndex: transaction.transactionIndex,
                blockHeight: transaction.blockHeight,
                confirmationsThreshold: Self.txStatusConfirmationsThreshold,
                date: Date(timeIntervalSince1970: Double(transaction.timestamp)),
                fee: transaction.fee.map { Decimal($0) / coinRate },
                failed: transaction.status == .invalid,
                lockInfo: lockInfo,
                conflictingHash: transaction.conflictingHash,
                showRawTransaction: transaction.status == .new || transaction.status == .invalid,
                amount: Decimal(transaction.amount) / coinRate,
                to: anyNotMineToAddress,
                sentToSelf: false,
                memo: memo,
                replaceable: transaction.replaceable && transaction.status != .invalid
            )
        case .sentToSelf:
            return BitcoinOutgoingTransactionRecord(
                token: token,
                source: transactionSource,
                uid: transaction.uid,
                transactionHash: transaction.transactionHash,
                transactionIndex: transaction.transactionIndex,
                blockHeight: transaction.blockHeight,
                confirmationsThreshold: Self.txStatusConfirmationsThreshold,
                date: Date(timeIntervalSince1970: Double(transaction.timestamp)),
                fee: transaction.fee.map { Decimal($0) / coinRate },
                failed: transaction.status == .invalid,
                lockInfo: lockInfo,
                conflictingHash: transaction.conflictingHash,
                showRawTransaction: transaction.status == .new || transaction.status == .invalid,
                amount: Decimal(transaction.amount) / coinRate,
                to: transaction.outputs.first(where: { !$0.changeOutput })?.address ?? transaction.outputs.first?.address,
                sentToSelf: true,
                memo: memo,
                replaceable: transaction.replaceable && transaction.status != .invalid
            )
        }
    }

    private func bitcoinBalanceData(balanceInfo: BalanceInfo) -> BitcoinBalanceData {
        BitcoinBalanceData(
            available: Decimal(balanceInfo.spendable) / coinRate,
            locked: Decimal(balanceInfo.unspendableTimeLocked) / coinRate,
            notRelayed: Decimal(balanceInfo.unspendableNotRelayed) / coinRate
        )
    }

    open var explorerTitle: String {
        fatalError("Must be overridden by subclass")
    }

    open func explorerUrl(transactionHash _: String) -> String? {
        fatalError("Must be overridden by subclass")
    }

    open func explorerUrl(address _: String) -> String? {
        fatalError("Must be overridden by subclass")
    }

    private var showSyncedUntil: Bool {
        if case .blockchair = syncMode {
            return false
        } else {
            return true
        }
    }
}

extension BitcoinBaseAdapter: IAdapter {
    var isMainNet: Bool {
        true
    }

    var debugInfo: String {
        abstractKit.debugInfo
    }

    func start() {
        balanceState = .syncing(progress: nil, remaining: nil, lastBlockDate: nil)
        abstractKit.start()
    }

    func stop() {
        abstractKit.stop()
    }

    func refresh() {
        abstractKit.start()
    }

    var statusInfo: [(String, Any)] {
        abstractKit.statusInfo
    }
}

extension BitcoinBaseAdapter: BitcoinCoreDelegate {
    func transactionsUpdated(inserted: [TransactionInfo], updated: [TransactionInfo]) {
        // Use a dedicated serial queue instead of the main queue so block sync
        // bursts do not pile up thousands of main-thread append/timer tasks.
        syncEventsQueue.async { [weak self] in
            guard let self else { return }
            self.pendingTxInserted.append(contentsOf: inserted)
            self.pendingTxUpdated.append(contentsOf: updated)
            guard !self.txFlushScheduled else { return }
            self.txFlushScheduled = true

            self.syncEventsQueue.asyncAfter(deadline: .now() + self.transactionUpdateThrottleInterval) { [weak self] in
                guard let self else { return }
                self.txFlushScheduled = false
                let batchInserted = self.pendingTxInserted
                let batchUpdated = self.pendingTxUpdated
                self.pendingTxInserted.removeAll(keepingCapacity: true)
                self.pendingTxUpdated.removeAll(keepingCapacity: true)

                // 2) CPU work (transactionRecord is the hot path) on background.
                self.transactionsConversionQueue.async { [weak self] in
                    guard let self else { return }
                    var records = [BitcoinTransactionRecord]()
                    for info in batchInserted {
                        records.append(self.transactionRecord(fromTransaction: info))
                    }
                    for info in batchUpdated {
                        records.append(self.transactionRecord(fromTransaction: info))
                    }
                    guard !records.isEmpty else { return }
                    self.transactionRecordsSubject.onNext(records)
                }
            }
        }
    }

    func transactionsDeleted(hashes _: [String]) {}

    func balanceUpdated(balance: BalanceInfo) {
        // Always refresh the main-thread cache so that IBalanceAdapter.balanceData
        // can return it in O(1). `abstractKit.balance` (the only other way to get
        // this data) iterates every UTXO and blocks the main thread for several
        // seconds on Safe3 wallets, which is what was causing the Severe Hang.
        let newData = bitcoinBalanceData(balanceInfo: balance)
        if Thread.isMainThread {
            cachedBitcoinBalanceData = newData
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.cachedBitcoinBalanceData = newData
            }
        }

        if throttleSyncEvents {
            pendingBalance = balance
            guard !balanceFlushScheduled else { return }
            balanceFlushScheduled = true
            syncEventsQueue.asyncAfter(deadline: .now() + syncEventThrottleInterval) { [weak self] in
                guard let self else { return }
                self.balanceFlushScheduled = false
                guard let pending = self.pendingBalance else { return }
                self.pendingBalance = nil
                self.bitcoinBalanceDataSubject.onNext(self.bitcoinBalanceData(balanceInfo: pending))
            }
            return
        }
        bitcoinBalanceDataSubject.onNext(newData)
    }

    func lastBlockInfoUpdated(lastBlockInfo info: BlockInfo) {
        if throttleSyncEvents {
            pendingLastBlockInfo = info
            guard !lastBlockInfoFlushScheduled else { return }
            lastBlockInfoFlushScheduled = true
            syncEventsQueue.asyncAfter(deadline: .now() + syncEventThrottleInterval) { [weak self] in
                guard let self else { return }
                self.lastBlockInfoFlushScheduled = false
                guard self.pendingLastBlockInfo != nil else { return }
                self.pendingLastBlockInfo = nil
                self.lastBlockUpdatedSubject.onNext(())
            }
            return
        }
        lastBlockUpdatedSubject.onNext(())
    }

    func kitStateUpdated(state: BitcoinCore.KitState) {
        // Terminal states (.synced / .notSynced) bypass the throttle — they
        // must always reach the UI so the spinner can settle. Only the
        // intermediate progress events (.syncing / .apiSyncing) are debounced.
        let shouldThrottle: Bool
        if throttleSyncEvents {
            switch state {
            case .synced, .notSynced:
                shouldThrottle = false
            case .syncing, .apiSyncing:
                shouldThrottle = true
            }
        } else {
            shouldThrottle = false
        }

        if shouldThrottle {
            pendingKitState = state
            guard !kitStateFlushScheduled else { return }
            kitStateFlushScheduled = true
            syncEventsQueue.asyncAfter(deadline: .now() + syncEventThrottleInterval) { [weak self] in
                guard let self else { return }
                self.kitStateFlushScheduled = false
                guard let pending = self.pendingKitState else { return }
                self.pendingKitState = nil
                self.applyKitState(pending)
            }
            return
        }
        clearPendingKitState()
        flushPendingSyncEvents()
        applyKitState(state)
    }

    private func clearPendingKitState() {
        pendingKitState = nil
        kitStateFlushScheduled = false
    }

    private func flushPendingSyncEvents() {
        balanceFlushScheduled = false
        lastBlockInfoFlushScheduled = false

        if let pendingBalance {
            self.pendingBalance = nil
            bitcoinBalanceDataSubject.onNext(bitcoinBalanceData(balanceInfo: pendingBalance))
        }

        if pendingLastBlockInfo != nil {
            pendingLastBlockInfo = nil
            lastBlockUpdatedSubject.onNext(())
        }
    }

    private func applyKitState(_ state: BitcoinCore.KitState) {
        switch state {
        case .synced:
            if case .synced = balanceState {
                return
            }

            balanceState = .synced
        case let .notSynced(error):
            let converted = error.convertedError

            if case let .notSynced(appError) = balanceState, "\(converted)" == "\(appError)" {
                return
            }

            balanceState = .notSynced(error: converted.localizedDescription)
        case let .syncing(progress):
            let newProgress = Int(progress * 100)
            let newDate = showSyncedUntil
                ? abstractKit.lastBlockInfo?.timestamp.map { Date(timeIntervalSince1970: Double($0)) }
                : nil

            if case let .syncing(currentProgress, _, currentDate) = balanceState, newProgress == currentProgress {
                if let currentDate, let newDate, currentDate.isSameDay(as: newDate) {
                    return
                }
            }

            balanceState = .syncing(progress: newProgress, remaining: nil, lastBlockDate: newDate)
        case let .apiSyncing(newCount):
            let newCountDescription = "balance.searching.count".localized("\(newCount)")
            if case let .customSyncing(_, secondary, _) = balanceState, newCountDescription == secondary {
                return
            }

            balanceState = .customSyncing(main: "balance.searching".localized(), secondary: newCountDescription, progress: nil)
        }
    }
}

extension BitcoinBaseAdapter: IBalanceAdapter {
    var balanceData: BalanceData {
        bitcoinBalanceData.balanceData
    }

    var balanceDataUpdatedObservable: Observable<BalanceData> {
        bitcoinBalanceDataSubject.map(\.balanceData).asObservable()
    }

    var balanceStateUpdatedObservable: Observable<AdapterState> {
        balanceStateSubject.asObservable()
    }
}

extension BitcoinBaseAdapter {
    var bitcoinBalanceData: BitcoinBalanceData {
        // Return the cache instead of recomputing. Calling `abstractKit.balance`
        // here triggers UnspentOutputProvider.balanceInfo, which iterates every
        // UTXO and blocks the main thread for several seconds on Safe3.
        cachedBitcoinBalanceData
    }

    var bitcoinBalanceDataObservable: Observable<BitcoinBalanceData> {
        bitcoinBalanceDataSubject.asObservable()
    }

    func availableBalance(params: SendParameters) -> Decimal {
        let amount = (try? abstractKit.maxSpendableValue(params: params)) ?? 0
        return Decimal(amount) / coinRate
    }

    func maximumSendAmount(pluginData: [UInt8: IBitcoinPluginData] = [:]) -> Decimal? {
        try? abstractKit.maxSpendLimit(pluginData: pluginData).flatMap { Decimal($0) / coinRate }
    }

    func minimumSendAmount(params: SendParameters) -> Decimal {
        do {
            return try Decimal(abstractKit.minSpendableValue(params: params)) / coinRate
        } catch {
            return 0
        }
    }

    func validate(address: String, pluginData: [UInt8: IPluginData]) throws {
        try abstractKit.validate(address: address, pluginData: pluginData)
    }

    func validate(address: String) throws {
        try validate(address: address, pluginData: [:])
    }

    func sendInfo(params: SendParameters) throws -> SendInfo {
        let info = try abstractKit.sendInfo(params: params)
        return SendInfo(
            unspentOutputs: info.unspentOutputs.map(\.info),
            fee: Decimal(info.fee) / coinRate,
            changeValue: info.changeValue.map { Decimal($0) / coinRate },
            changeAddress: info.changeAddress?.stringValue
        )
    }
    
    var bitcoinCore: BitcoinCore {
        abstractKit.bitcoinCore
    }

    func unspentOutputs(filters: UtxoFilters) -> [UnspentOutputInfo] {
        abstractKit.unspentOutputs(filters: filters)
    }

    @discardableResult func send(params: SendParameters) throws -> FullTransaction {
        try abstractKit.send(params: params)
    }

    func sendSingle(params: SendParameters, logger: Logger) -> Single<Void> {
        Single.create { [weak self] observer in
            do {
                if let adapter = self {
                    logger.debug("Sending to \(String(reflecting: adapter.abstractKit))", save: true)
                    try adapter.send(params: params)
                }
                observer(.success(()))
            } catch {
                observer(.error(error))
            }

            return Disposables.create()
        }
    }

    func convertToSatoshi(value: Decimal) -> Int {
        let coinValue: Decimal = value * coinRate
        let handler = NSDecimalNumberHandler(roundingMode: .down, scale: Int16(truncatingIfNeeded: 0), raiseOnExactness: false, raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false)
        return NSDecimalNumber(decimal: coinValue).rounding(accordingToBehavior: handler).intValue
    }

    func convertToKitSortMode(sort: TransactionDataSortMode) -> TransactionDataSortType {
        switch sort {
        case .shuffle: return .shuffle
        case .bip69: return .bip69
        }
    }
}

extension BitcoinBaseAdapter: ITransactionsAdapter {
    var lastBlockInfo: LastBlockInfo? {
        abstractKit.lastBlockInfo.map { LastBlockInfo(height: $0.height, timestamp: $0.timestamp) }
    }

    var syncingObservable: Observable<Void> {
        balanceStateSubject.map { _ in () }
    }

    var lastBlockUpdatedObservable: Observable<Void> {
        lastBlockUpdatedSubject.asObservable()
    }

    func transactionsObservable(token _: Token?, filter: TransactionTypeFilter, address _: String?) -> Observable<[TransactionRecord]> {
        transactionRecordsSubject.asObservable()
            .map { transactions in
                transactions.compactMap { transaction -> TransactionRecord? in
                    switch (transaction, filter) {
                    case (_, .all):
                        return transaction
                    case (is BitcoinIncomingTransactionRecord, .incoming):
                        return transaction
                    case (is BitcoinOutgoingTransactionRecord, .outgoing):
                        return transaction
                    case let (tx as BitcoinOutgoingTransactionRecord, .incoming):
                        return tx.sentToSelf ? transaction : nil
                    default:
                        return nil
                    }
                }
            }
            .filter { !$0.isEmpty }
    }

    var additionalTokenQueries: [TokenQuery] {
        []
    }

    func transactionsSingle(paginationData: String?, token _: Token?, filter: TransactionTypeFilter, address _: String?, limit: Int) -> Single<[TransactionRecord]> {
        let bitcoinFilter: TransactionFilterType?
        switch filter {
        case .all: bitcoinFilter = nil
        case .incoming: bitcoinFilter = .incoming
        case .outgoing: bitcoinFilter = .outgoing
        default: return Single.just([])
        }

        return Single.create { [weak self] observer in
            guard let self else {
                observer(.success([]))
                return Disposables.create()
            }

            let workItem = DispatchWorkItem { [weak self] in
                guard let self else {
                    observer(.success([]))
                    return
                }

                let transactions = self.abstractKit.transactions(fromUid: paginationData, type: bitcoinFilter, descending: true, limit: limit)
                    .map { self.transactionRecord(fromTransaction: $0) }

                observer(.success(transactions))
            }

            self.transactionsConversionQueue.async(execute: workItem)
            return Disposables.create {
                workItem.cancel()
            }
        }
    }

    func allTransactionsAfter(paginationData: String?) -> Single<[TransactionRecord]> {
        return Single.create { [weak self] observer in
            guard let self else {
                observer(.success([]))
                return Disposables.create()
            }

            let workItem = DispatchWorkItem { [weak self] in
                guard let self else {
                    observer(.success([]))
                    return
                }

                let transactions = self.abstractKit.transactions(fromUid: paginationData, type: nil, descending: false, limit: nil)
                    .map { self.transactionRecord(fromTransaction: $0) }

                observer(.success(transactions))
            }

            self.transactionsConversionQueue.async(execute: workItem)
            return Disposables.create {
                workItem.cancel()
            }
        }
    }

    func rawTransaction(hash: String) -> String? {
        abstractKit.rawTransaction(transactionHash: hash)
    }

    func speedUpTransactionInfo(transactionHash: String) -> (originalTransactionSize: Int, feeRange: Range<Int>)? {
        abstractKit.speedUpTransactionInfo(transactionHash: transactionHash)
    }

    func cancelTransactionInfo(transactionHash: String) -> (originalTransactionSize: Int, feeRange: Range<Int>)? {
        abstractKit.cancelTransactionInfo(transactionHash: transactionHash)
    }

    func speedUpTransaction(transactionHash: String, minFee: Int) throws -> (replacment: ReplacementTransaction, record: BitcoinTransactionRecord) {
        let replacment = try abstractKit.speedUpTransaction(transactionHash: transactionHash, minFee: minFee)
        return (replacment: replacment, record: transactionRecord(fromTransaction: replacment.info))
    }

    func cancelTransaction(transactionHash: String, minFee: Int) throws -> (replacment: ReplacementTransaction, record: BitcoinTransactionRecord) {
        let replacment = try abstractKit.cancelTransaction(transactionHash: transactionHash, minFee: minFee)
        return (replacment: replacment, record: transactionRecord(fromTransaction: replacment.info))
    }

    func send(replacementTransaction: ReplacementTransaction) throws -> FullTransaction {
        try abstractKit.send(replacementTransaction: replacementTransaction)
    }
}

extension BitcoinBaseAdapter: IDepositAdapter, IHDDepositAdapter {
    var receiveAddress: DepositAddress {
        DepositAddress(abstractKit.receiveAddress())
    }

    func usedAddresses(change: Bool) -> [UsedAddress] {
        abstractKit.usedAddresses(change: change).map {
            let url = explorerUrl(address: $0.address).flatMap { URL(string: $0) }
            return UsedAddress(index: $0.index, address: $0.address, explorerUrl: url, transactionsCount: nil)
        }.sorted { $0.index < $1.index }
    }
}

extension BitcoinBaseAdapter {
    struct BitcoinBalanceData {
        let available: Decimal
        let locked: Decimal
        let notRelayed: Decimal

        var balanceData: BalanceData {
            BalanceData(total: available + locked + notRelayed, available: available)
        }
    }
}

class DepositAddress {
    let address: String

    init(_ receiveAddress: String) {
        address = receiveAddress
    }
}

public struct UsedAddress: Hashable {
    let index: Int
    let address: String
    let explorerUrl: URL?
    let transactionsCount: Int?

    public func hash(into hasher: inout Hasher) {
        hasher.combine(index)
        hasher.combine(address)
        hasher.combine(explorerUrl?.absoluteString)
        hasher.combine(transactionsCount)
    }
}

struct SendInfo {
    static let empty: Self = .init(unspentOutputs: [], fee: 0, changeValue: nil, changeAddress: nil)

    public let unspentOutputs: [UnspentOutputInfo]
    public let fee: Decimal
    public let changeValue: Decimal?
    public let changeAddress: String?
}
