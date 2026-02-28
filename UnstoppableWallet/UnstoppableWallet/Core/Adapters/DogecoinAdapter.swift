import DogecoinKit
import BitcoinCore
import Foundation
import RxSwift
import MarketKit
import HdWalletKit

let dogeCoinUid = "dogecoin"
let dogeCoinName = "DOGE"
let dogeCoinCode = "DOGE"

class DogecoinAdapter: BitcoinBaseAdapter {
    private let dogecoinKit: DogecoinKit.Kit

    init(wallet: Wallet, syncMode: BitcoinCore.SyncMode) throws {
        let effectiveSyncMode: BitcoinCore.SyncMode = syncMode == .full ? .full : .blockchair
        let networkType: DogecoinKit.Kit.NetworkType = .mainNet
        let logger = Core.shared.logger.scoped(with: "DogeecoinKit")
        
        let hasher: (Data) -> Data = { data in
            let params = DogecoinKit.Kit.defaultScryptParams

            let result = try? BackupCryptoHelper.makeScrypt(
                pass: data,
                salt: data,
                dkLen: params.length,
                N: params.N,
                r: params.r,
                p: params.p
            )
            return result ?? Data()
        }
        
        switch wallet.account.type {
        case .mnemonic:
            guard let seed = wallet.account.type.mnemonicSeed else {
                throw AdapterError.unsupportedAccount
            }

//            guard let derivation = wallet.token.type.derivation else {
//                throw AdapterError.wrongParameters
//            }

            dogecoinKit = try DogecoinKit.Kit(
                seed: seed,
                purpose: .bip44,//derivation.purpose,
                walletId: wallet.account.id,
                syncMode: effectiveSyncMode,
                hasher: hasher,
                networkType: networkType,
                confirmationsThreshold: BitcoinBaseAdapter.confirmationsThreshold,
                logger: logger
            )
        case let .hdExtendedKey(key):
//            guard let derivation = wallet.token.type.derivation else {
//                throw AdapterError.wrongParameters
//            }

            dogecoinKit = try DogecoinKit.Kit(
                extendedKey: key,
                purpose: .bip44,//derivation.purpose,
                walletId: wallet.account.id,
                syncMode: effectiveSyncMode,
                hasher: hasher,
                networkType: networkType,
                confirmationsThreshold: BitcoinBaseAdapter.confirmationsThreshold,
                logger: logger
            )
        default:
            throw AdapterError.unsupportedAccount
        }

        super.init(abstractKit: dogecoinKit, wallet: wallet, syncMode: effectiveSyncMode)

        dogecoinKit.delegate = self
    }

    override var explorerTitle: String {
        "blockchair.com"
    }

    override func explorerUrl(transactionHash: String) -> String? {
        "https://blockchair.com/dogecoin/transaction/" + transactionHash
    }
    
    override func explorerUrl(address: String) -> String? {
        "https://blockchair.com/dogecoin/address/" + address
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
