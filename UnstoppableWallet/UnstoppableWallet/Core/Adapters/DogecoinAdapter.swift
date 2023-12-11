import DogecoinKit
import BitcoinCore
import RxSwift
import MarketKit
import HdWalletKit

let dogeCoinUid = "dogecoin"
let dogeCoinName = "DOGE"
let dogeCoinCode = "DOGE"

class DogecoinAdapter: BitcoinBaseAdapter {
    private let dogecoinKit: DogecoinKit.Kit

    init(wallet: Wallet, syncMode: BitcoinCore.SyncMode) throws {
        let networkType: DogecoinKit.Kit.NetworkType = .mainNet
        let logger = App.shared.logger.scoped(with: "DogeecoinKit")

        switch wallet.account.type {
        case .mnemonic:
            guard let seed = wallet.account.type.mnemonicSeed else {
                throw AdapterError.unsupportedAccount
            }

            guard let derivation = wallet.coinSettings.derivation else {
                throw AdapterError.wrongParameters
            }

            dogecoinKit = try DogecoinKit.Kit(
                    seed: seed,
                    purpose: derivation.purpose,
                    walletId: wallet.account.id,
                    syncMode: syncMode,
                    networkType: networkType,
                    confirmationsThreshold: BitcoinBaseAdapter.confirmationsThreshold,
                    logger: logger
            )
        case let .hdExtendedKey(key):
            guard let derivation = wallet.coinSettings.derivation else {
                throw AdapterError.wrongParameters
            }

            dogecoinKit = try DogecoinKit.Kit(
                    extendedKey: key,
                    purpose: derivation.purpose,
                    walletId: wallet.account.id,
                    syncMode: syncMode,
                    networkType: networkType,
                    confirmationsThreshold: BitcoinBaseAdapter.confirmationsThreshold,
                    logger: logger
            )
        default:
            throw AdapterError.unsupportedAccount
        }

        super.init(abstractKit: dogecoinKit, wallet: wallet)

        dogecoinKit.delegate = self
    }

    override var explorerTitle: String {
        "blockchair.com"
    }

    override func explorerUrl(transactionHash: String) -> String? {
        "https://blockchair.com/dogecoin/transaction/" + transactionHash
    }

}

extension DogecoinAdapter: ISendBitcoinAdapter {

    var blockchainType: BlockchainType {
        .dogecoin
    }

}

extension DogecoinAdapter {

    static func clear(except excludedWalletIds: [String]) throws {
        try Kit.clear(exceptFor: excludedWalletIds)
    }

}
