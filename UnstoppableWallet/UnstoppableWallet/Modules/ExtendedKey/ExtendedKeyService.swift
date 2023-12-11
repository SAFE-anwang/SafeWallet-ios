import Foundation
import RxSwift
import RxRelay
import HdWalletKit
import BitcoinKit
import BitcoinCashKit
import LitecoinKit
import DogecoinKit
import DashKit
import SafeCoinKit

class ExtendedKeyService {
    let mode: ExtendedKeyModule.Mode
    private let accountType: AccountType

    private var derivation: MnemonicDerivation = .bip44
    private var blockchain: Blockchain = .bitcoin
    private var account: Int = 0

    private let itemRelay = PublishRelay<Item>()
    private(set) var item: Item = .empty {
        didSet {
            itemRelay.accept(item)
        }
    }

    init(mode: ExtendedKeyModule.Mode, accountType: AccountType) {
        self.mode = mode
        self.accountType = accountType

        syncDerivation()
        syncItem()
    }

    private func syncDerivation() {
        switch accountType {
        case .hdExtendedKey(let key):
            let derivations = key.purposes.map { $0.mnemonicDerivation }
            if !derivations.contains(derivation) {
                derivation = derivations[0]
            }
        default: ()
        }

        syncBlockchain()
    }

    private func syncBlockchain() {
        if !supportedBlockchains.contains(blockchain) {
            blockchain = supportedBlockchains[0]
        }
    }

    private var derivationSwitchable: Bool {
        switch accountType {
        case .mnemonic: return true
        default: return false
        }
    }

    private var blockchainSwitchable: Bool {
        supportedBlockchains.count > 1
    }

    private var resolvedBlockchain: Blockchain? {
        switch mode {
        case .bip32RootKey:
            return nil
        case .accountExtendedPrivateKey, .accountExtendedPublicKey:
            switch accountType {
            case .mnemonic:
                return blockchain
            case .hdExtendedKey(let extendedKey):
                switch extendedKey.derivedType {
                case .master: return blockchain
                default: return nil
                }
            default:
                return nil
            }
        }
    }

    private var resolvedAccount: Int? {
        switch mode {
        case .bip32RootKey: return nil
        case .accountExtendedPrivateKey, .accountExtendedPublicKey:
            switch accountType {
            case .mnemonic:
                return account
            case .hdExtendedKey(let extendedKey):
                switch extendedKey.derivedType {
                case .master: return account
                default: return nil
                }
            default:
                return nil
            }
        }
    }

    private var resolvedKey: String? {
        switch accountType {
        case .mnemonic:
            guard let rootKey = rootKey(seed: accountType.mnemonicSeed) else {
                return nil
            }

            return key(rootKey: rootKey)
        case .hdExtendedKey(let extendedKey):
            switch extendedKey {
            case .private(let privateKey):
                switch extendedKey.derivedType {
                case .master:
                    return key(rootKey: privateKey)
                case .account:
                    switch mode {
                    case .accountExtendedPrivateKey: return privateKey.extended()
                    case .accountExtendedPublicKey: return privateKey.publicKey().extended()
                    default: return nil
                    }
                default: return nil
                }
            case .public(let publicKey):
                switch extendedKey.derivedType {
                case .account:
                    switch mode {
                    case .accountExtendedPublicKey: return publicKey.extended()
                    default: return nil
                    }
                default: return nil
                }
            }
        default:
            return nil
        }
    }

    private var keyIsPrivate: Bool {
        switch mode {
        case .bip32RootKey, .accountExtendedPrivateKey: return true
        case .accountExtendedPublicKey: return false
        }
    }

    private func syncItem() {
        item = Item(
                derivation: derivation,
                derivationSwitchable: derivationSwitchable,
                blockchain: resolvedBlockchain,
                blockchainSwitchable: blockchainSwitchable,
                account: resolvedAccount,
                key: resolvedKey,
                keyIsPrivate: keyIsPrivate
        )
    }

    private func key(rootKey: HDPrivateKey) -> String? {
        let keychain = HDKeychain(privateKey: rootKey)

        switch mode {
        case .bip32RootKey:
            return rootKey.extended()
        case .accountExtendedPrivateKey:
            let version = try? HDExtendedKeyVersion(purpose: derivation.purpose, coinType: blockchain.extendedKeyCoinType, isPrivate: true)
            return try? keychain.derivedKey(path: "m/\(derivation.purpose.rawValue)'/\(blockchain.coinType)'/\(account)'").extended(customVersion: version)
        case .accountExtendedPublicKey:
            let version = try? HDExtendedKeyVersion(purpose: derivation.purpose, coinType: blockchain.extendedKeyCoinType, isPrivate: false)
            return try? keychain.derivedKey(path: "m/\(derivation.purpose.rawValue)'/\(blockchain.coinType)'/\(account)'").publicKey().extended(customVersion: version)
        }
    }

    private func rootKey(seed: Data?) -> HDPrivateKey? {
        guard let seed = seed else {
            return nil
        }

        guard let version = try? HDExtendedKeyVersion(purpose: derivation.purpose, coinType: blockchain.extendedKeyCoinType) else {
            return nil
        }

        return HDPrivateKey(seed: seed, xPrivKey: version.rawValue)
    }

}

extension ExtendedKeyService {

    var itemObservable: Observable<Item> {
        itemRelay.asObservable()
    }

//    var supportedBlockchains: [Blockchain] {
//        switch accountType {
//        case .hdExtendedKey(let key):
//            switch key.info.coinType {
//            case .bitcoin:
//                switch derivation {
//                case .bip44: return [.bitcoin, .bitcoinCash, .litecoin, .dash]
//                case .bip49: return [.bitcoin, .litecoin]
//                case .bip84: return [.bitcoin, .litecoin]
//                }
//            case .litecoin:
//                return [.litecoin]
//            }
//        default:
//            switch derivation {
//            case .bip44: return [.bitcoin, .bitcoinCash, .litecoin, .dash]
//            case .bip49: return [.bitcoin, .litecoin]
//            case .bip84: return [.bitcoin, .litecoin]
//            }
//        }
//    }
    var supportedBlockchains: [Blockchain] {
        var coinTypesDerivableFromKey = [HDExtendedKeyVersion.ExtendedKeyCoinType]()
        if case .hdExtendedKey(let key) = accountType {
            coinTypesDerivableFromKey.append(contentsOf: key.coinTypes)
        }

        switch derivation {
        case .bip44:
            if coinTypesDerivableFromKey.count == 1, coinTypesDerivableFromKey[0] == .litecoin {
                return [.litecoin]
            } else {
                return [.bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash]
            }
        default:
            if coinTypesDerivableFromKey.count == 1, coinTypesDerivableFromKey[0] == .litecoin {
                return [.litecoin]
            } else {
                return [.bitcoin, .litecoin]
            }
        }
    }

    func set(derivation: MnemonicDerivation) {
        self.derivation = derivation
        syncDerivation()
        syncItem()
    }

    func set(blockchain: Blockchain) {
        self.blockchain = blockchain
        syncBlockchain()
        syncItem()
    }

    func set(account: Int) {
        self.account = account
        syncItem()
    }

}

extension ExtendedKeyService {

    struct Item {
        let derivation: MnemonicDerivation
        let derivationSwitchable: Bool
        let blockchain: Blockchain?
        let blockchainSwitchable: Bool
        let account: Int?
        let key: String?
        let keyIsPrivate: Bool

        static var empty: Item {
            Item(derivation: .bip44, derivationSwitchable: false, blockchain: nil, blockchainSwitchable: false, account: nil, key: nil, keyIsPrivate: false)
        }
    }

    enum Blockchain {
        case bitcoin
        case bitcoinCash
        case litecoin
        case dogecoin
        case dash
        case safe
        
        var title: String {
            switch self {
            case .bitcoin: return "Bitcoin"
            case .bitcoinCash: return "Bitcoin Cash"
            case .litecoin: return "Litecoin"
            case .dogecoin: return "Doge"
            case .dash: return "Dash"
            case .safe: return "Safe"
            }
        }

        var extendedKeyCoinType: HDExtendedKeyVersion.ExtendedKeyCoinType {
            switch self {
            case .bitcoin, .bitcoinCash, .dash, .safe: return .bitcoin
            case .dogecoin, .litecoin: return .litecoin
            }
        }

        var coinType: UInt32 {
            switch self {
            case .bitcoin: return BitcoinKit.MainNet().coinType
            case .bitcoinCash: return BitcoinCashKit.MainNet().coinType
            case .litecoin: return LitecoinKit.MainNet().coinType
            case .dogecoin: return DogecoinKit.MainNet().coinType
            case .dash: return DashKit.MainNet().coinType
            case .safe: return SafeCoinKit.MainNet().coinType
            }
        }
    }

}
