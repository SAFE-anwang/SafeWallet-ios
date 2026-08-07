import EvmKit
import Foundation
import HdWalletKit
import TronKit

final class ChildWalletDerivationService {
    func evmPrivateKey(account: Account, childWallet: ChildWallet, chain: Chain) throws -> Data {
        guard case .mnemonic = account.type,
              let seed = account.type.mnemonicSeed
        else {
            throw ChildWalletError.unsupportedAccountType
        }

        let hdWallet = HDWallet(seed: seed, coinType: chain.coinType, xPrivKey: HDExtendedKeyVersion.xprv.rawValue)
        return try hdWallet.privateKey(account: 0, index: childWallet.derivationIndex, chain: .external).raw
    }

    func evmAddress(account: Account, childWallet: ChildWallet, chain: Chain) throws -> EvmKit.Address {
        EvmKit.Signer.address(privateKey: try evmPrivateKey(account: account, childWallet: childWallet, chain: chain))
    }

    func evmSigner(account: Account, childWallet: ChildWallet, chain: Chain) throws -> EvmKit.Signer {
        EvmKit.Signer.instance(privateKey: try evmPrivateKey(account: account, childWallet: childWallet, chain: chain), chain: chain)
    }

    func tronPrivateKey(account: Account, childWallet: ChildWallet) throws -> Data {
        guard case .mnemonic = account.type,
              let seed = account.type.mnemonicSeed
        else {
            throw ChildWalletError.unsupportedAccountType
        }

        let hdWallet = HDWallet(seed: seed, coinType: 195, xPrivKey: HDExtendedKeyVersion.xprv.rawValue)
        return try hdWallet.privateKey(account: 0, index: childWallet.derivationIndex, chain: .external).raw
    }

    func tronAddress(account: Account, childWallet: ChildWallet) throws -> TronKit.Address {
        try TronKit.Signer.address(privateKey: try tronPrivateKey(account: account, childWallet: childWallet))
    }

    func tronSigner(account: Account, childWallet: ChildWallet) throws -> TronKit.Signer {
        try TronKit.Signer.instance(privateKey: try tronPrivateKey(account: account, childWallet: childWallet))
    }
}
