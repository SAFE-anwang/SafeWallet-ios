import Foundation
import Hodler
import SafeCoinKit
import RxSwift
import HsToolKit
import BitcoinCore
import MarketKit
import HdWalletKit
import Checkpoints

class SafeCoinAdapter: BitcoinBaseAdapter {
    private let feeRate = 10
    public  let safeCoinKit: SafeCoinKit.Kit
        
    init(wallet: Wallet, syncMode: BitcoinCore.SyncMode) throws {
        let networkType: SafeCoinKit.Kit.NetworkType = .mainNet
        let logger = App.shared.logger.scoped(with: "SafeCoinKit")

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

        super.init(abstractKit: safeCoinKit, wallet: wallet)

        safeCoinKit.delegate = self
    }

    override var explorerTitle: String {
        "anwang.com"
    }

    override func explorerUrl(transactionHash: String) -> String? {
         "https://chain.anwang.com/tx/" + transactionHash
    }

}

extension SafeCoinAdapter: DashKitDelegate {

    public func transactionsUpdated(inserted: [DashTransactionInfo], updated: [DashTransactionInfo]) {
        var records = [BitcoinTransactionRecord]()

        for info in inserted {
            records.append(transactionRecord(fromTransaction: info))
        }
        for info in updated {
            records.append(transactionRecord(fromTransaction: info))
        }

        transactionRecordsSubject.onNext(records)
    }

}

extension SafeCoinAdapter: ISendSafeCoinAdapter {
    
    var blockchainType: BlockchainType {
        .safe
    }
    
    func minimumSendAmountSafe(address: String?) -> Decimal {
        minimumSendAmount(address: address)
    }
    
    func validateSafe(address: String) throws {
        try validate(address: address)
    }
    
    func availableBalanceSafe(address: String?) -> Decimal {
        availableBalance(feeRate: feeRate, address: address)
    }
    
    func feeSafe(amount: Decimal, address: String?) -> Decimal {
        fee(amount: amount, feeRate: feeRate, address: address)
    }
    
    func convertFeeSafe(amount: Decimal, address: String?) -> Decimal {
        // 增加兑换WSAFE流量手续费
        var convertFeeRate = feeRate
        convertFeeRate += 50
        return fee(amount: amount, feeRate: convertFeeRate, address: address)
    }
    
    func sendSingle(amount: Decimal, address: String, sortMode: TransactionDataSortMode, logger: HsToolKit.Logger, lockedTimeInterval: HodlerPlugin.LockTimeInterval?, reverseHex: String?) -> RxSwift.Single<Void> {
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
                    _ = try adapter.safeCoinKit.sendSafe(to: address, value: satoshiAmount, feeRate: convertFeeRate, sortType: sortType, pluginData: [:], unlockedHeight: unlockedHeight, reverseHex: newReverseHex)
                }
                observer(.success(()))
            } catch {
                observer(.error(error))
            }

            return Disposables.create()
        }

    }
    
    private func convertToSatoshi(value: Decimal) -> Int {
        let coinValue: Decimal = value * coinRate
        let handler = NSDecimalNumberHandler(roundingMode: .plain, scale: Int16(truncatingIfNeeded: 0), raiseOnExactness: false, raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false)
        return NSDecimalNumber(decimal: coinValue).rounding(accordingToBehavior: handler).intValue
    }

    private func convertToKitSortMode(sort: TransactionDataSortMode) -> TransactionDataSortType {
        switch sort {
        case .shuffle: return .shuffle
        case .bip69: return .bip69
        }
    }
    
    public func fallbackBlock(date: CheckpointData.FallbackDate) {
        if let _ = safeCoinKit.lastBlockInfo {
            do {
                let checkpoint = try Checkpoint(safe: date)
                let startBlockHeight = checkpoint.block.height
                
                guard let lastBlockHeight = safeCoinKit.lastBlockInfo?.height, startBlockHeight <= lastBlockHeight else { return }
                let blocksList = safeCoinKit.bitcoinCore.storage.blocks(from: startBlockHeight, to: lastBlockHeight, ascending: false)
                if blocksList.count > 0 {
                    safeCoinKit.stop()
                    try safeCoinKit.bitcoinCore.storage.delete(blocks: blocksList)
                    safeCoinKit.bitcoinCore.updateLastBlockInfo(network: .main, fallbackDate: date)
                    safeCoinKit.start()
                }
            }catch {}
        }
    }


}

public struct BlockInfo {
    public let headerHash: String
    public let height: Int
    public let timestamp: Int?
}

extension SafeCoinAdapter {

    static func clear(except excludedWalletIds: [String]) throws {
        try Kit.clear(exceptFor: excludedWalletIds)
    }

}
