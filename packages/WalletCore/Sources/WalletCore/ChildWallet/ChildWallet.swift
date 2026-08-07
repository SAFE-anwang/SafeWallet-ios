import Foundation
import MarketKit

public struct ChildWallet: Codable, Equatable, Identifiable {
    public enum CreationSource: Codable, Equatable, Sendable {
        case userCreated

        public init(from decoder: Decoder) throws {
            self = .userCreated
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode("userCreated")
        }
    }

    static let minDerivationIndex = 1
    static let maxDerivationIndex = 500

    public let id: String
    public let parentAccountId: String
    public let derivationIndex: Int
    public var name: String
    public var isHidden: Bool
    public let createdAt: TimeInterval
    public let creationSource: CreationSource?

    public init(
        id: String = UUID().uuidString,
        parentAccountId: String,
        derivationIndex: Int,
        name: String,
        isHidden: Bool = false,
        createdAt: TimeInterval = Date().timeIntervalSince1970,
        creationSource: CreationSource? = .userCreated
    ) throws {
        guard Self.isValid(derivationIndex: derivationIndex) else {
            throw ChildWalletError.invalidDerivationIndex
        }

        self.id = id
        self.parentAccountId = parentAccountId
        self.derivationIndex = derivationIndex
        self.name = name
        self.isHidden = isHidden
        self.createdAt = createdAt
        self.creationSource = creationSource
    }

    static func isValid(derivationIndex: Int) -> Bool {
        (minDerivationIndex ... maxDerivationIndex).contains(derivationIndex)
    }
}

struct ChildWalletIdentity: Equatable {
    let account: Account
    let childWallet: ChildWallet?

    var isRoot: Bool {
        childWallet == nil
    }

    var childWalletId: String? {
        childWallet?.id
    }

    var derivationIndex: Int? {
        childWallet?.derivationIndex
    }

    init(account: Account, childWallet: ChildWallet?) {
        self.account = account
        self.childWallet = childWallet
    }
}

struct ChildWalletKitCacheKey: Equatable {
    let accountId: String
    let childWalletId: String?
    let blockchainType: BlockchainType
}

enum ChildWalletError: Error {
    case invalidDerivationIndex
    case duplicateDerivationIndex
    case childWalletNotFound
    case childWalletUnsupported(String)
    case unsupportedAccountType
    case missingMnemonicSeed
    case indexedDerivationNotImplemented(String)
    case noRpcSource(BlockchainType)
    case invalidName
    case storageUnavailable(String)
}

extension ChildWalletError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidDerivationIndex:
            return "Child wallet derivation index is outside the supported 1...500 range."
        case .duplicateDerivationIndex:
            return "Child wallet derivation index already exists for this parent account."
        case .childWalletNotFound:
            return "Child wallet was not found."
        case let .childWalletUnsupported(reason):
            return "Child wallet operation is unsupported: \(reason)."
        case .unsupportedAccountType:
            return "Child wallets currently require a supported mnemonic parent account."
        case .missingMnemonicSeed:
            return "Mnemonic seed is unavailable for child wallet derivation."
        case let .indexedDerivationNotImplemented(reason):
            return "Indexed child wallet derivation is not implemented: \(reason)."
        case let .noRpcSource(blockchainType):
            return "No HTTP RPC source is available for \(blockchainType.uid)."
        case .invalidName:
            return "Child wallet name cannot be empty."
        case let .storageUnavailable(reason):
            return "Child wallet storage is unavailable: \(reason)."
        }
    }
}
