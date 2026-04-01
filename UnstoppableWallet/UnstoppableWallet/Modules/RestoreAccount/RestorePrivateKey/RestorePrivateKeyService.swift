import BitcoinCore
import BitcoinKit
import EvmKit
import Foundation
import HdWalletKit
import MarketKit
import stellarsdk

enum PrivateKeyType: String, CaseIterable {
    case evm = "EVM Private Key"
    case hdExtendedKey = "HD Extended Key"
    case stellarSecretKey = "Stellar Secret Key"
    case bitcoinPrivateKey = "Bitcoin Private Key"
    case bitcoinWif = "Bitcoin WIF"
    case bitcoinMiniKey = "Bitcoin Mini Key"
    case bitcoinBrainWallet = "Bitcoin Brain Wallet"
    case bitcoinBip38 = "Bitcoin BIP38"
    case unsupported = "Unsupported"

    var blockchainTypes: [BlockchainType] {
        switch self {
        case .evm:
            return [.ethereum, .binanceSmartChain, .polygon, .avalanche, .gnosis, .fantom, .arbitrumOne, .optimism, .base, .zkSync, .safe4]
        case .hdExtendedKey:
            return [.bitcoin, .litecoin, .bitcoinCash, .dash, .dogecoin]
        case .stellarSecretKey:
            return [.stellar]
        case .bitcoinPrivateKey, .bitcoinWif, .bitcoinMiniKey, .bitcoinBrainWallet, .bitcoinBip38:
            return [.bitcoin, .litecoin, .bitcoinCash, .dash, .dogecoin]
        case .unsupported:
            return []
        }
    }
}

class RestorePrivateKeyService {
    private var bip38Password: String?
    private(set) var wifRoutingContext: WifRoutingContext?

    func setBip38Password(_ password: String?) {
        self.bip38Password = password
    }

    func clearBip38Password() {
        self.bip38Password = nil
    }

    func accountType(text: String, forceType: PrivateKeyType? = nil) throws -> AccountType {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        wifRoutingContext = nil

        guard !text.isEmpty else {
            throw RestoreError.emptyText
        }

        if let forcedType = forceType {
            return try parseWithForcedType(text: text, type: forcedType)
        }

        do {
            let extendedKey = try HDExtendedKey(extendedKey: text)

            switch extendedKey {
            case .private:
                switch extendedKey.derivedType {
                case .master, .account:
                    return .hdExtendedKey(key: extendedKey)
                default:
                    throw RestoreError.notSupportedDerivedType
                }
            default:
                throw RestoreError.nonPrivateKey
            }
        } catch {}

        do {
            let privateKey = try Signer.privateKey(string: normalizeHexPrefix(text))
            return .evmPrivateKey(data: privateKey)
        } catch {}

        do {
            _ = try KeyPair(secretSeed: text)
            return .stellarSecretKey(secretSeed: text)
        } catch {}

        do {
            return try parseBitcoinPrivateKey(text: text)
        } catch let error as RestoreError {
            if case .unsupportedKeyType = error {
                // Keep trying other key families
            } else {
                throw error
            }
        } catch {
            // Keep compatibility with previous fallback behavior
        }

        throw RestoreError.noValidKey
    }

    private func parseWithForcedType(text: String, type: PrivateKeyType) throws -> AccountType {
        switch type {
        case .evm:
            let privateKey = try Signer.privateKey(string: normalizeHexPrefix(text))
            return .evmPrivateKey(data: privateKey)

        case .hdExtendedKey:
            let extendedKey = try HDExtendedKey(extendedKey: text)
            return .hdExtendedKey(key: extendedKey)

        case .stellarSecretKey:
            _ = try KeyPair(secretSeed: text)
            return .stellarSecretKey(secretSeed: text)

        case .bitcoinPrivateKey:
            return try parseBitcoinHexPrivateKey(text: text)

        case .bitcoinWif:
            return try parseBitcoinWifPrivateKey(text: text)

        case .bitcoinMiniKey:
            return try parseBitcoinMiniKey(text: text)

        case .bitcoinBrainWallet:
            return try parseBrainWallet(text: text)

        case .bitcoinBip38:
            guard let password = bip38Password else {
                throw RestoreError.bip38PasswordRequired
            }
            return try parseBip38PrivateKey(text: text, password: password)

        case .unsupported:
            throw RestoreError.unsupportedKeyType
        }
    }

    private func parseBitcoinPrivateKey(text: String) throws -> AccountType {
        if let format = BitcoinPrivateKeyParser.detectFormat(text) {
            switch format {
            case .hex:
                return try parseBitcoinHexPrivateKey(text: text)

            case .wifMainNet, .wifCompressedMainNet, .wifTestNet, .wifCompressedTestNet:
                return try parseBitcoinWifPrivateKey(text: text)

            case .miniKey:
                return try parseBitcoinMiniKey(text: text)

            case .bip38Encrypted:
                guard let password = bip38Password else {
                    throw RestoreError.bip38PasswordRequired
                }
                return try parseBip38PrivateKey(text: text, password: password)

            case .brainWalletSingle, .brainWalletDouble:
                return try parseBrainWallet(text: text)
            }
        }

        if BitcoinPrivateKeyParser.isBrainWalletCandidate(text) {
            return try parseBrainWallet(text: text)
        }

        if text.count == 64 && text.allSatisfy({ $0.isHexDigit }) {
            return try parseBitcoinHexPrivateKey(text: text)
        }

        throw RestoreError.unsupportedKeyType
    }

    private func parseBitcoinHexPrivateKey(text: String) throws -> AccountType {
        do {
            let privateKeyData = try BitcoinPrivateKeyParser.parsePrivateKey(text, format: .hex)
            return .btcPrivateKey(data: privateKeyData, compressed: true, blockchainType: .bitcoin)
        } catch let error as BitcoinKeyError {
            throw map(bitcoinError: error)
        } catch {
            throw RestoreError.invalidPrivateKey
        }
    }

    private func parseBitcoinWifPrivateKey(text: String) throws -> AccountType {
        do {
            let parsed = try BitcoinPrivateKeyParser.decodeWif(text)
            let blockchainType = blockchainType(wifPrefix: parsed.wifPrefix, isTestNet: parsed.isTestNet)
            let allowedBitcoinDerivations: Set<MnemonicDerivation>?
            let requireManualDerivationSelection: Bool
            if blockchainType == .bitcoin || blockchainType == .litecoin {
                if parsed.isCompressed {
                    allowedBitcoinDerivations = Set(MnemonicDerivation.allCases)
                    requireManualDerivationSelection = true
                } else {
                    allowedBitcoinDerivations = [.bip44]
                    requireManualDerivationSelection = false
                }
            } else {
                allowedBitcoinDerivations = nil
                requireManualDerivationSelection = false
            }

            wifRoutingContext = WifRoutingContext(
                blockchainType: blockchainType,
                allowedBitcoinDerivations: allowedBitcoinDerivations,
                skipCoinSelection: true,
                requireManualDerivationSelection: requireManualDerivationSelection
            )

            return .btcPrivateKey(data: parsed.privateKey, compressed: parsed.isCompressed, blockchainType: blockchainType)
        } catch let error as BitcoinKeyError {
            throw map(bitcoinError: error)
        } catch {
            throw RestoreError.invalidPrivateKey
        }
    }

    private func blockchainType(wifPrefix: UInt8?, isTestNet: Bool) -> BlockchainType {
        guard !isTestNet else {
            return .bitcoin
        }

        switch wifPrefix {
        case 0xB0:
            return .litecoin
        case 0x9E:
            return .dogecoin
        case 0xCC:
            return .dash
        default:
            return .bitcoin
        }
    }

    private func parseBitcoinMiniKey(text: String) throws -> AccountType {
        do {
            let parsed = try BitcoinPrivateKeyParser.parsePrivateKeyInfo(text, format: .miniKey)
            return .btcPrivateKey(data: parsed.privateKey, compressed: parsed.isCompressed, blockchainType: .bitcoin)
        } catch let error as BitcoinKeyError {
            throw map(bitcoinError: error)
        } catch {
            throw RestoreError.invalidPrivateKey
        }
    }

    private func parseBrainWallet(text: String) throws -> AccountType {
        do {
            let parsed = try BitcoinPrivateKeyParser.parsePrivateKeyInfo(text, format: .brainWalletSingle)
            return .btcPrivateKey(data: parsed.privateKey, compressed: parsed.isCompressed, blockchainType: .bitcoin)
        } catch let error as BitcoinKeyError {
            throw map(bitcoinError: error)
        } catch {
            throw RestoreError.invalidPrivateKey
        }
    }

    private func parseBip38PrivateKey(text: String, password: String) throws -> AccountType {
        do {
            let parsed = try BitcoinPrivateKeyParser.parsePrivateKeyInfo(text, format: .bip38Encrypted, bip38Password: password)
            return .btcPrivateKey(data: parsed.privateKey, compressed: parsed.isCompressed, blockchainType: .bitcoin)
        } catch let error as BitcoinKeyError {
            throw map(bitcoinError: error)
        } catch {
            throw RestoreError.invalidBip38Key
        }
    }

    private func map(bitcoinError: BitcoinKeyError) -> RestoreError {
        switch bitcoinError {
        case .decryptionFailed:
            return .decryptionFailed
        case .invalidWifChecksum:
            return .invalidWifChecksum
        case .invalidBip38Format, .invalidBip38Checksum, .invalidBip38Key:
            return .invalidBip38Key
        case .invalidPrivateKey, .invalidHexLength, .invalidFormat, .invalidMiniKeyLength, .invalidMiniKeyChecksum, .invalidWifPrefix, .invalidBrainWalletPassword, .unsupportedFormat, .addressGenerationFailed:
            return .invalidPrivateKey
        }
    }

    func detectPrivateKeyType(_ text: String) -> PrivateKeyType {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let normalizedForEvm = normalizeHexPrefix(trimmed)
        if normalizedForEvm.count == 64, normalizedForEvm.allSatisfy(\.isHexDigit) {
            do {
                _ = try Signer.privateKey(string: normalizedForEvm)
                return .evm
            } catch {}
        }

        if let format = BitcoinPrivateKeyParser.detectFormat(trimmed) {
            switch format {
            case .hex:
                return .bitcoinPrivateKey
            case .wifMainNet, .wifCompressedMainNet, .wifTestNet, .wifCompressedTestNet:
                return .bitcoinWif
            case .miniKey:
                return .bitcoinMiniKey
            case .bip38Encrypted:
                return .bitcoinBip38
            case .brainWalletSingle, .brainWalletDouble:
                return .bitcoinBrainWallet
            }
        }

        if BitcoinPrivateKeyParser.isBrainWalletCandidate(trimmed) {
            return .bitcoinBrainWallet
        }

        do {
            let _ = try HDExtendedKey(extendedKey: trimmed)
            return .hdExtendedKey
        } catch {}

        do {
            _ = try KeyPair(secretSeed: trimmed)
            return .stellarSecretKey
        } catch {}

        return .unsupported
    }

    func supportedTokenTypes(for type: PrivateKeyType) -> [TokenQuery] {
        switch type {
        case .evm:
            return [
                TokenQuery(blockchainType: .ethereum, tokenType: .native),
                TokenQuery(blockchainType: .binanceSmartChain, tokenType: .native),
                TokenQuery(blockchainType: .polygon, tokenType: .native),
                TokenQuery(blockchainType: .avalanche, tokenType: .native),
                TokenQuery(blockchainType: .optimism, tokenType: .native),
                TokenQuery(blockchainType: .arbitrumOne, tokenType: .native),
                TokenQuery(blockchainType: .base, tokenType: .native),
                TokenQuery(blockchainType: .zkSync, tokenType: .native),
                TokenQuery(blockchainType: .gnosis, tokenType: .native),
                TokenQuery(blockchainType: .fantom, tokenType: .native),
                TokenQuery(blockchainType: .safe4, tokenType: .native),
            ]
        case .bitcoinPrivateKey, .bitcoinWif, .bitcoinMiniKey, .bitcoinBrainWallet, .bitcoinBip38:
            let blockchainTypes: [BlockchainType] = [
                .bitcoin,
                .litecoin,
                .bitcoinCash,
                .dash,
                .dogecoin,
            ]

            return blockchainTypes.flatMap(\.nativeTokenQueries)
        case .hdExtendedKey:
            return [
                TokenQuery(blockchainType: .bitcoin, tokenType: .derived(derivation: MnemonicDerivation.default.derivation)),
                TokenQuery(blockchainType: .litecoin, tokenType: .derived(derivation: MnemonicDerivation.default.derivation)),
                TokenQuery(blockchainType: .bitcoinCash, tokenType: .addressType(type: BitcoinCashCoinType.default.addressType)),
                TokenQuery(blockchainType: .dash, tokenType: .native),
                TokenQuery(blockchainType: .dogecoin, tokenType: .native),
            ]
        case .stellarSecretKey:
            return [
                TokenQuery(blockchainType: .stellar, tokenType: .native),
            ]
        case .unsupported:
            return []
        }
    }

    private func normalizeHexPrefix(_ text: String) -> String {
        if text.hasPrefix("0x") || text.hasPrefix("0X") {
            return String(text.dropFirst(2))
        }
        return text
    }
}

extension RestorePrivateKeyService {
    struct WifRoutingContext {
        let blockchainType: BlockchainType
        let allowedBitcoinDerivations: Set<MnemonicDerivation>?
        let skipCoinSelection: Bool
        let requireManualDerivationSelection: Bool
    }

    enum RestoreError: Error, LocalizedError {
        case emptyText
        case notSupportedDerivedType
        case nonPrivateKey
        case noValidKey
        case unsupportedKeyType
        case bip38PasswordRequired
        case invalidPrivateKey
        case invalidWifChecksum
        case invalidBip38Key
        case decryptionFailed

        var errorDescription: String? {
            switch self {
            case .emptyText:
                return "restore.private_key.empty_text"
            case .notSupportedDerivedType:
                return "restore.private_key.not_supported_derived_type"
            case .nonPrivateKey:
                return "restore.private_key.non_private_key"
            case .noValidKey:
                return "restore.private_key.no_valid_key"
            case .unsupportedKeyType:
                return "restore.private_key.unsupported_type"
            case .bip38PasswordRequired:
                return "restore.private_key.bip38_password_required"
            case .invalidPrivateKey:
                return "restore.private_key.invalid_key"
            case .invalidWifChecksum:
                return "restore.private_key.invalid_wif_checksum"
            case .invalidBip38Key:
                return "restore.private_key.invalid_bip38_key"
            case .decryptionFailed:
                return "restore.private_key.decryption_failed"
            }
        }
    }
}
