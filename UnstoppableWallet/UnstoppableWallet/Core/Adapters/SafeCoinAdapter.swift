import Foundation
import SafeCoinKit
import RxSwift
import HsToolKit
import BitcoinCore
import MarketKit
import HdWalletKit

class SafeCoinAdapter: BitcoinBaseAdapter {
    private let feeRate = 1

    private let safeCoinKit: SafeCoinKit.Kit

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
        "safe.org"
    }

    override func explorerUrl(transactionHash: String) -> String? {
         "https://anwang.com/img/logos/safe.png"
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

extension SafeCoinAdapter: ISendBitcoinAdapter {

    var blockchainType: BlockchainType {
        .unsupported(uid: safeCoinUid)
    }

}

extension SafeCoinAdapter {

    static func clear(except excludedWalletIds: [String]) throws {
        try Kit.clear(exceptFor: excludedWalletIds)
    }

}

