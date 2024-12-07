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

        super.init(abstractKit: safeCoinKit, wallet: wallet, syncMode: syncMode)

        safeCoinKit.delegate = self
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
    
}

extension SafeCoinAdapter: SafeCoinKitDelegate {

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

extension SafeCoinAdapter {
    static func clear(except excludedWalletIds: [String]) throws {
        try Kit.clear(exceptFor: excludedWalletIds)
    }
}

extension SafeCoinAdapter: ISendSafeCoinAdapter {
    func availableBalanceSafe(feeRate: Int, address: String?, memo: String?, unspentOutputs: [UnspentOutputInfo]?, pluginData: [UInt8: IBitcoinPluginData] = [:]) -> Decimal {
        availableBalance(feeRate: feeRate, address: address, memo: memo, unspentOutputs: unspentOutputs, pluginData: pluginData)
    }

    func validateSafe(address: String) throws {
        try validate(address: address)
    }

    func sendInfoSafe(amount: Decimal, feeRate: Int, address: String?, memo: String?, unspentOutputs: [UnspentOutputInfo]?, pluginData: [UInt8: IBitcoinPluginData] = [:]) throws -> SendInfo {
        return try sendInfo(amount: amount, feeRate: feeRate, address: address, memo: memo, unspentOutputs: unspentOutputs, pluginData: pluginData)
    }

    var blockchainType: BlockchainType {
        .safe
    }
    
    func maximumSendAmountSafe(pluginData: [UInt8: IBitcoinPluginData]) -> Decimal? {
        maximumSendAmount(pluginData: pluginData)
    }
    
    func minimumSendAmountSafe(address: String?) -> Decimal {
        minimumSendAmount(address: address)
    }
        
    func convertFeeSafe(amount: Decimal, address: String?, memo: String?, unspentOutputs: [UnspentOutputInfo]?, pluginData: [UInt8: IBitcoinPluginData] = [:]) throws -> SendInfo {
        // 增加兑换WSAFE流量手续费
        var convertFeeRate = feeRate
        convertFeeRate += 50
        return try sendInfo(amount: Decimal(convertFeeRate), feeRate: feeRate, address: address, memo: memo, unspentOutputs: unspentOutputs, pluginData: pluginData)
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
                    _ = try adapter.safeCoinKit.sendSafe(to: address, memo: memo, value: satoshiAmount, feeRate: convertFeeRate, sortType: sortType, rbfEnabled: rbfEnabled, unlockedHeight: unlockedHeight, reverseHex: newReverseHex)
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

public struct BlockInfo {
    public let headerHash: String
    public let height: Int
    public let timestamp: Int?
}
