import Foundation
import Hodler
import SafeCoinKit
import RxSwift
import HsToolKit
import BitcoinCore
import MarketKit
import HdWalletKit
import Checkpoints
import BigInt

class SafeCoinAdapter: BitcoinBaseAdapter {
    private let feeRate = 10
    public  let safeCoinKit: SafeCoinKit.Kit
    private let transactionsUpdateQueue = DispatchQueue(label: "\(AppConfig.label).safe-coin-adapter.transactions", qos: .utility)
    private let walletTransactionSource: TransactionSource
    private let transactionScanCacheLock = NSLock()
    private var transactionScanCache = [String: TransactionScanSnapshot]()
    
    // Merge incoming Safe3 transaction events on a dedicated serial queue and
    // flush them in batches, so sync bursts do not schedule work on the main
    // runloop before the throttle window decides whether to process the batch.
    private var pendingInserted: [DashTransactionInfo] = []
    private var pendingUpdated: [DashTransactionInfo] = []
    private var transactionsFlushScheduled = false

    override var transactionUpdateThrottleInterval: TimeInterval {
        balanceState.syncing ? 2.5 : 0.35
    }

    override var syncEventThrottleInterval: TimeInterval {
        balanceState.syncing ? 4.0 : 1.0
    }
        
    init(wallet: Wallet, syncMode: BitcoinCore.SyncMode) throws {
        let networkType: SafeCoinKit.Kit.NetworkType = .mainNet
        let logger = Core.shared.logger.scoped(with: "SafeCoinKit")
        walletTransactionSource = wallet.transactionSource

        switch wallet.account.type {
        case .mnemonic:
            guard let seed = wallet.account.type.mnemonicSeed else {
                throw AdapterError.unsupportedAccount
            }

            safeCoinKit = try SafeCoinKit.Kit(
                    seed: seed,
                    walletId: wallet.account.id,
                    syncMode: syncMode,
                    networkType: networkType,
                    confirmationsThreshold: BitcoinBaseAdapter.confirmationsThreshold,
                    logger: logger
            )
        case let .hdExtendedKey(key):
            safeCoinKit = try SafeCoinKit.Kit(
                    extendedKey: key,
                    walletId: wallet.account.id,
                    syncMode: syncMode,
                    networkType: networkType,
                    confirmationsThreshold: BitcoinBaseAdapter.confirmationsThreshold,
                    logger: logger
            )
        default:
            throw AdapterError.unsupportedAccount
        }

        super.init(abstractKit: safeCoinKit, wallet: wallet, syncMode: syncMode)

        safeCoinKit.delegate = self
        // Enable sync event throttling to reduce main-thread pressure during Safe3 sync
        self.throttleSyncEvents = true
    }

    override var explorerTitle: String {
        "anwang.com"
    }

    override func explorerUrl(transactionHash: String) -> String? {
         "https://chain.anwang.com/tx/" + transactionHash
    }
    
    override func explorerUrl(address: String) -> String? {
        "https://chain.anwang.com/address/" + address
    }
    
    func masterPrivateKey(wallet: Wallet) throws -> HDPrivateKey {
        guard let seed = wallet.account.type.mnemonicSeed else {
            throw AdapterError.unsupportedAccount
        }
        let masterPrivateKey = HDPrivateKey(seed: seed, xPrivKey: Purpose.bip44.rawValue)
        return masterPrivateKey
    }
    
    func hdWallet(_ wallet: Wallet) throws -> HDWallet {
        guard let seed = wallet.account.type.mnemonicSeed else {
            throw AdapterError.unsupportedAccount
        }
        let masterPrivateKey = HDPrivateKey(seed: seed, xPrivKey: Purpose.bip44.rawValue)
        let hdWallet = HDWallet(masterKey: masterPrivateKey, coinType: 5, purpose: Purpose.bip44)
        return hdWallet
    }

    override func transactionRecord(fromTransaction transaction: TransactionInfo) -> BitcoinTransactionRecord {
        let snapshot = scanSnapshot(for: transaction)
        let lockInfo = lockInfo(from: snapshot.lockSource)
        let date = Date(timeIntervalSince1970: Double(transaction.timestamp))
        let fee = transaction.fee.map { Decimal($0) / coinRate }
        let failed = transaction.status == .invalid
        let showRawTransaction = transaction.status == .new || transaction.status == .invalid
        let amount = Decimal(transaction.amount) / coinRate

        switch transaction.type {
        case .incoming:
            return BitcoinIncomingTransactionRecord(
                token: token,
                source: walletTransactionSource,
                uid: transaction.uid,
                transactionHash: transaction.transactionHash,
                transactionIndex: transaction.transactionIndex,
                blockHeight: transaction.blockHeight,
                confirmationsThreshold: BitcoinBaseAdapter.txStatusConfirmationsThreshold,
                date: date,
                fee: fee,
                failed: failed,
                lockInfo: lockInfo,
                conflictingHash: transaction.conflictingHash,
                showRawTransaction: showRawTransaction,
                amount: amount,
                from: snapshot.fromAddress,
                memo: snapshot.memo
            )
        case .outgoing:
            return BitcoinOutgoingTransactionRecord(
                token: token,
                source: walletTransactionSource,
                uid: transaction.uid,
                transactionHash: transaction.transactionHash,
                transactionIndex: transaction.transactionIndex,
                blockHeight: transaction.blockHeight,
                confirmationsThreshold: BitcoinBaseAdapter.txStatusConfirmationsThreshold,
                date: date,
                fee: fee,
                failed: failed,
                lockInfo: lockInfo,
                conflictingHash: transaction.conflictingHash,
                showRawTransaction: showRawTransaction,
                amount: amount,
                to: snapshot.toAddress,
                sentToSelf: false,
                memo: snapshot.memo,
                replaceable: transaction.replaceable && transaction.status != .invalid
            )
        case .sentToSelf:
            return BitcoinOutgoingTransactionRecord(
                token: token,
                source: walletTransactionSource,
                uid: transaction.uid,
                transactionHash: transaction.transactionHash,
                transactionIndex: transaction.transactionIndex,
                blockHeight: transaction.blockHeight,
                confirmationsThreshold: BitcoinBaseAdapter.txStatusConfirmationsThreshold,
                date: date,
                fee: fee,
                failed: failed,
                lockInfo: lockInfo,
                conflictingHash: transaction.conflictingHash,
                showRawTransaction: showRawTransaction,
                amount: amount,
                to: snapshot.sentToSelfAddress,
                sentToSelf: true,
                memo: snapshot.memo,
                replaceable: transaction.replaceable && transaction.status != .invalid
            )
        }
    }

}

private extension SafeCoinAdapter {
    struct TransactionScanSnapshot {
        let transactionHash: String
        let transactionIndex: Int
        let inputCount: Int
        let outputCount: Int
        let amount: Int
        let type: TransactionType
        let fromAddress: String?
        let toAddress: String?
        let sentToSelfAddress: String?
        let memo: String?
        let lockSource: LockSource?

        func matches(_ transaction: TransactionInfo) -> Bool {
            transactionHash == transaction.transactionHash &&
                transactionIndex == transaction.transactionIndex &&
                inputCount == transaction.inputs.count &&
                outputCount == transaction.outputs.count &&
                amount == transaction.amount &&
                type == transaction.type
        }
    }

    enum LockSource {
        case unlockedHeight(originalAddress: String, lockTimeInterval: HodlerPlugin.LockTimeInterval, unlockedHeight: Int)
        case approximateUnlockTime(originalAddress: String, lockTimeInterval: HodlerPlugin.LockTimeInterval, approximateUnlockTime: Int)
    }
}

extension SafeCoinAdapter: SafeCoinKitDelegate {
    public func transactionsUpdated(inserted: [DashTransactionInfo], updated: [DashTransactionInfo]) {
        transactionsUpdateQueue.async { [weak self] in
            guard let self else { return }
            self.enqueueTransactions(inserted: inserted, updated: updated)
        }
    }
}

private extension SafeCoinAdapter {
    func enqueueTransactions(inserted: [DashTransactionInfo], updated: [DashTransactionInfo]) {
        pendingInserted.append(contentsOf: inserted)
        pendingUpdated.append(contentsOf: updated)

        guard !transactionsFlushScheduled else {
            return
        }

        transactionsFlushScheduled = true
        let interval = transactionUpdateThrottleInterval

        transactionsUpdateQueue.asyncAfter(deadline: .now() + interval) { [weak self] in
            self?.flushPendingTransactions()
        }
    }

    func flushPendingTransactions() {
        transactionsFlushScheduled = false

        let batchInserted = pendingInserted
        let batchUpdated = pendingUpdated
        pendingInserted.removeAll(keepingCapacity: true)
        pendingUpdated.removeAll(keepingCapacity: true)

        transactionsUpdateQueue.async { [weak self] in
            self?.publishMergedTransactions(inserted: batchInserted, updated: batchUpdated)
        }
    }

    func publishMergedTransactions(inserted: [DashTransactionInfo], updated: [DashTransactionInfo]) {
        guard transactionRecordsSubject.hasObservers else {
            return
        }

        let uniqueInfos = mergedUniqueTransactions(inserted: inserted, updated: updated)
        guard !uniqueInfos.isEmpty else {
            return
        }

        var records = [BitcoinTransactionRecord]()
        records.reserveCapacity(uniqueInfos.count)

        for info in uniqueInfos {
            records.append(transactionRecord(fromTransaction: info))
        }

        guard !records.isEmpty else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.transactionRecordsSubject.onNext(records)
        }
    }

    func scanSnapshot(for transaction: TransactionInfo) -> TransactionScanSnapshot {
        transactionScanCacheLock.lock()
        if let cached = transactionScanCache[transaction.uid], cached.matches(transaction) {
            transactionScanCacheLock.unlock()
            return cached
        }
        transactionScanCacheLock.unlock()

        var lockSource: LockSource?
        var fromAddress: String?
        var toAddress: String?
        var sentToSelfAddress: String?
        var memo: String?

        for input in transaction.inputs where fromAddress == nil {
            fromAddress = input.address
        }

        for output in transaction.outputs {
            if output.memo != nil {
                memo = output.memo
            }

            if sentToSelfAddress == nil, !output.changeOutput {
                sentToSelfAddress = output.address
            }

            guard output.value > 0 else {
                continue
            }

            if let unlockedHeight = output.unlockedHeight,
               unlockedHeight > 0,
               let hodlerOutputData = output.pluginData as? HodlerOutputData {
                lockSource = .unlockedHeight(
                    originalAddress: output.address ?? "__",
                    lockTimeInterval: hodlerOutputData.lockTimeInterval,
                    unlockedHeight: unlockedHeight
                )
            } else if let pluginId = output.pluginId,
                      pluginId == HodlerPlugin.id,
                      let hodlerOutputData = output.pluginData as? HodlerOutputData,
                      let approximateUnlockTime = hodlerOutputData.approximateUnlockTime {
                lockSource = .approximateUnlockTime(
                    originalAddress: hodlerOutputData.addressString,
                    lockTimeInterval: hodlerOutputData.lockTimeInterval,
                    approximateUnlockTime: approximateUnlockTime
                )
            }

            if toAddress == nil, let address = output.address, !output.mine {
                toAddress = address
            }
        }

        let snapshot = TransactionScanSnapshot(
            transactionHash: transaction.transactionHash,
            transactionIndex: transaction.transactionIndex,
            inputCount: transaction.inputs.count,
            outputCount: transaction.outputs.count,
            amount: transaction.amount,
            type: transaction.type,
            fromAddress: fromAddress,
            toAddress: toAddress,
            sentToSelfAddress: sentToSelfAddress ?? transaction.outputs.first?.address,
            memo: memo,
            lockSource: lockSource
        )

        transactionScanCacheLock.lock()
        transactionScanCache[transaction.uid] = snapshot
        transactionScanCacheLock.unlock()
        return snapshot
    }

    func lockInfo(from source: LockSource?) -> TransactionLockInfo? {
        guard let source else {
            return nil
        }

        switch source {
        case let .unlockedHeight(originalAddress, lockTimeInterval, unlockedHeight):
            let approxUnlockTime = (safeCoinKit.lastBlockInfo?.timestamp ?? 0) + ((unlockedHeight - (safeCoinKit.lastBlockInfo?.height ?? 0)) * 30)
            return TransactionLockInfo(
                lockedUntil: Date(timeIntervalSince1970: Double(approxUnlockTime)),
                originalAddress: originalAddress,
                lockTimeInterval: lockTimeInterval,
                unlockedHeight: unlockedHeight
            )
        case let .approximateUnlockTime(originalAddress, lockTimeInterval, approximateUnlockTime):
            return TransactionLockInfo(
                lockedUntil: Date(timeIntervalSince1970: Double(approximateUnlockTime)),
                originalAddress: originalAddress,
                lockTimeInterval: lockTimeInterval,
                unlockedHeight: nil
            )
        }
    }

    func mergedUniqueTransactions(inserted: [DashTransactionInfo], updated: [DashTransactionInfo]) -> [DashTransactionInfo] {
        var orderedInfos = [DashTransactionInfo]()
        var indexByUid = [String: Int]()

        for info in inserted {
            if indexByUid[info.uid] == nil {
                indexByUid[info.uid] = orderedInfos.count
                orderedInfos.append(info)
            } else if let index = indexByUid[info.uid] {
                orderedInfos[index] = info
            }
        }

        for info in updated {
            if let index = indexByUid[info.uid] {
                orderedInfos[index] = info
            } else {
                indexByUid[info.uid] = orderedInfos.count
                orderedInfos.append(info)
            }
        }

        return orderedInfos
    }
}

extension SafeCoinAdapter {
    static func clear(except excludedWalletIds: [String]) throws {
        try Kit.clear(exceptFor: excludedWalletIds)
    }
}

extension SafeCoinAdapter: ISendSafeCoinAdapter {
    func availableBalanceSafe(feeRate: Int, address: String?, memo: String?, unspentOutputs: [UnspentOutputInfo]?, pluginData: [UInt8: IBitcoinPluginData] = [:]) -> Decimal {
        let params = SendParameters(address: address, feeRate: feeRate, memo: memo, unspentOutputs: unspentOutputs, pluginData: pluginData)
        return availableBalance(params: params)
//        availableBalance(feeRate: feeRate, address: address, memo: memo, unspentOutputs: unspentOutputs, pluginData: pluginData)
    }

    func validateSafe(address: String) throws {
        try validate(address: address)
    }

    func sendInfoSafe(amount: Decimal, feeRate: Int, address: String?, memo: String?, unspentOutputs: [UnspentOutputInfo]?, pluginData: [UInt8: IBitcoinPluginData] = [:]) throws -> SendInfo {
        let satoshiAmount = convertToSatoshi(value: amount)
        let params = SendParameters(address: address, value: satoshiAmount, feeRate: feeRate, memo: memo, unspentOutputs: unspentOutputs, pluginData: pluginData)
        return try sendInfo(params: params)//sendInfo(amount: amount, feeRate: feeRate, address: address, memo: memo, unspentOutputs: unspentOutputs, pluginData: pluginData)
    }

    var blockchainType: BlockchainType {
        .safe
    }
    
    func maximumSendAmountSafe(pluginData: [UInt8: IBitcoinPluginData]) -> Decimal? {
        maximumSendAmount(pluginData: pluginData)
    }
    
    func minimumSendAmountSafe(address: String?) -> Decimal {
        minimumSendAmount(params: SendParameters(address: address))
//        minimumSendAmount(address: address)
    }
        
    func convertFeeSafe(amount: Decimal, address: String?, memo: String?, unspentOutputs: [UnspentOutputInfo]?, pluginData: [UInt8: IBitcoinPluginData] = [:]) throws -> SendInfo {
        // 增加兑换WSAFE流量手续费
        var convertFeeRate = feeRate
        convertFeeRate += 50
        let satoshiAmount = convertToSatoshi(value: amount)
        let params = SendParameters(address: address, value: satoshiAmount, feeRate: feeRate, memo: memo, unspentOutputs: unspentOutputs, pluginData: pluginData)
        return try sendInfo(params: params)//sendInfo(amount: Decimal(convertFeeRate), feeRate: feeRate, address: address, memo: memo, unspentOutputs: unspentOutputs, pluginData: pluginData)
    }
    
    func sendSingle(amount: Decimal, address: String, memo: String?, feeRate: Int, unspentOutputs: [UnspentOutputInfo]?, pluginData: [UInt8: IBitcoinPluginData] = [:], sortMode: TransactionDataSortMode, rbfEnabled: Bool, logger: Logger, lockedTimeInterval: HodlerPlugin.LockTimeInterval?, reverseHex: String?) -> Single<Void> {
        var unlockedHeight = 0
        if let lockedValueInSeconds = lockedTimeInterval?.valueInSeconds {
            let step = 86400 * Int(lockedValueInSeconds/(30 * 24 * 60 * 60))
            unlockedHeight = (safeCoinKit.lastBlockInfo?.height ?? 0) + step
        }
        
        let satoshiAmount = convertToSatoshi(value: amount)
        let sortType = convertToKitSortMode(sort: sortMode)

        return Single.create { [weak self] observer in
            do {
                // 增加兑换WSAFE流量手续费
                var convertFeeRate = self!.feeRate
                var newReverseHex = reverseHex
                if let reverseHex = reverseHex, reverseHex.starts(with: "73616665") {
                    convertFeeRate += 50
                } else if let reverseHex = reverseHex, !reverseHex.starts(with: "73616665") {
                    convertFeeRate += 50
                    if let lineLock = reverseHex.stringToObj(LineLock.self) {
                        // 设置最新区块高度
                        lineLock.lastHeight = self?.safeCoinKit.lastBlockInfo?.height ?? 0
                        let value = self!.convertToSatoshi(value: Decimal(string: lineLock.lockedValue)!)
                        lineLock.lockedValue = "\(value)"
                        newReverseHex = lineLock.reverseHex()
                    }

                }
                if let adapter = self {
                    let params = SendParameters(address: address, value: satoshiAmount, feeRate: convertFeeRate, sortType: sortType, rbfEnabled: rbfEnabled, memo: memo, unlockedHeight: unlockedHeight, reverseHex: newReverseHex)
                    _ = try adapter.safeCoinKit.sendSafe(params: params)//sendSafe(to: address, memo: memo, value: satoshiAmount, feeRate: convertFeeRate, sortType: sortType, rbfEnabled: rbfEnabled, unlockedHeight: unlockedHeight, reverseHex: newReverseHex)
                }
                observer(.success(()))
            } catch {
                observer(.error(error))
            }

            return Disposables.create()
        }

    }
    
//    private func convertToSatoshi(value: Decimal) -> Int {
//        let coinValue: Decimal = value * coinRate
//        let handler = NSDecimalNumberHandler(roundingMode: .plain, scale: Int16(truncatingIfNeeded: 0), raiseOnExactness: false, raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false)
//        return NSDecimalNumber(decimal: coinValue).rounding(accordingToBehavior: handler).intValue
//    }

//    private func convertToKitSortMode(sort: TransactionDataSortMode) -> TransactionDataSortType {
//        switch sort {
//        case .shuffle: return .shuffle
//        case .bip69: return .bip69
//        }
//    }
    
    public func fallbackBlock(date: CheckpointData.FallbackDate) {
        if let _ = safeCoinKit.lastBlockInfo {
            do {
                let checkpoint = try Checkpoint(safe: date)
                let startBlockHeight = checkpoint.block.height
                
                guard let lastBlockHeight = safeCoinKit.lastBlockInfo?.height, startBlockHeight <= lastBlockHeight else { return }

                let blocksList = safeCoinKit.bitcoinCore.storage.blocks(from: startBlockHeight, to: lastBlockHeight, ascending: false)
                if blocksList.count > 0 {
                    safeCoinKit.stop()
                    safeCoinKit.bitcoinCore.stopDownload()
                    try safeCoinKit.bitcoinCore.storage.delete(blocks: blocksList)
                    if let network = self.safeCoinKit.safeMainNet {
                        safeCoinKit.updateLastBlockInfo(network: network, syncMode: .api, fallbackDate: date)
                    }
                    safeCoinKit.start()
                }
            }catch {}

        }
    }
}
extension SafeCoinAdapter {
    
    func coinValue(value: BigUInt) -> AppValue {
        let decimalValue = Decimal(bigUInt: value, decimals: token.decimals) ?? 0
        return coinValue(value: decimalValue)
    }
    
    func coinValue(value: Decimal) -> AppValue {
        AppValue(kind: .token(token: token), value: value)
    }

}
