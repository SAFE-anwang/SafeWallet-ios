import BigInt
import Foundation
import Web3Core

enum SRC721ContractType: String, CaseIterable, Codable, Hashable, Identifiable {
    case standard
    case burnable
    case unknown

    var id: Self { self }

    var title: String {
        switch self {
        case .standard: return "safe_zone.src721.type.standard".localized
        case .burnable: return "safe_zone.src721.type.burnable".localized
        case .unknown: return "safe_zone.src721.type.unknown".localized
        }
    }

    var canBurn: Bool { self == .burnable }
}

enum SRC721TransactionStatus: String, Codable, Hashable {
    case pending
    case confirmed
    case failed
}

struct SRC721BatchOperationError: LocalizedError {
    let submittedHashes: [String]
    let confirmedHashes: [String]
    let underlying: Error

    init(submittedHashes: [String], confirmedHashes: [String] = [], underlying: Error) {
        self.submittedHashes = submittedHashes
        self.confirmedHashes = confirmedHashes
        self.underlying = underlying
    }

    var errorDescription: String? { underlying.localizedDescription }
}

struct SRC721ContractRecord: Codable, Hashable, Identifiable {
    let accountId: String
    let chainId: Int
    let walletAddress: String
    var contractAddress: String
    let predictedContractAddress: String?
    let creatorAddress: String
    var currentOwnerAddress: String?
    let contractType: SRC721ContractType
    var name: String
    var symbol: String
    var baseURI: String
    var maxSupply: String
    var mintPrice: String
    var deployTransactionHash: String?
    var transactionStatus: SRC721TransactionStatus
    var validationStatus: String
    let createdAt: Date

    var id: String { "\(chainId):\(contractAddress.lowercased())" }
    var maxSupplyValue: BigUInt { BigUInt(maxSupply) ?? 0 }
    var mintPriceValue: BigUInt { BigUInt(mintPrice) ?? 0 }

    var isPending: Bool { transactionStatus == .pending }
    var isReadOnly: Bool {
        guard let currentOwnerAddress else { return false }
        return currentOwnerAddress.lowercased() != walletAddress.lowercased()
    }
}

struct SRC721ContractState: Equatable {
    let name: String
    let symbol: String
    let ownerAddress: String
    let baseURI: String
    let maxSupply: BigUInt
    let totalSupply: BigUInt
    let remainSupply: BigUInt
    let mintPrice: BigUInt
    let walletBalance: BigUInt
    let safeBalance: BigUInt
    let orgName: String
    let description: String
    let officialURL: String
    let whitePaperURL: String
    let logo: Data

    var isSoldOut: Bool { remainSupply == 0 }
}

struct SRC721TokenState: Equatable {
    let tokenId: BigUInt
    let ownerAddress: String
    let approvedAddress: String
    let tokenURI: String
}

struct SRC721TransactionRecord: Codable, Hashable, Identifiable {
    let id: UUID
    let accountId: String
    let chainId: Int
    let walletAddress: String
    let contractAddress: String
    let operation: String
    let tokenId: String?
    let transactionHash: String
    var status: SRC721TransactionStatus
    var errorMessage: String?
    let createdAt: Date
}

enum SRC721ValidationError: LocalizedError {
    case missingAccount
    case invalidAddress(String)
    case invalidAmount(String)
    case invalidURL
    case invalidAllowList
    case invalidTokenId
    case invalidLogo
    case emptyField(String)
    case textTooLong(String)
    case invalidContract
    case transactionTimeout
    case missingSigner

    var errorDescription: String? {
        switch self {
        case .missingAccount: return "safe_zone.src721.error.account".localized
        case let .invalidAddress(field): return "safe_zone.src721.error.address".localized(field)
        case let .invalidAmount(field): return "safe_zone.src721.error.amount".localized(field)
        case .invalidURL: return "safe_zone.src721.error.url".localized
        case .invalidAllowList: return "safe_zone.src721.error.allow_list".localized
        case .invalidTokenId: return "safe_zone.src721.error.token_id".localized
        case .invalidLogo: return "safe_zone.src721.error.logo".localized
        case let .emptyField(field): return "safe_zone.src721.error.required".localized(field)
        case let .textTooLong(field): return "safe_zone.src721.error.too_long".localized(field)
        case .invalidContract: return "safe_zone.src721.error.contract".localized
        case .transactionTimeout: return "safe_zone.src721.error.timeout".localized
        case .missingSigner: return "safe_zone.src721.error.signer".localized
        }
    }
}

enum SRC721Validation {
    static let zeroAddress = "0x0000000000000000000000000000000000000000"
    static let nameMaxUTF8Length = 64
    static let symbolMaxUTF8Length = 16
    static let baseURIMaxUTF8Length = 512
    static let uint256Max = (BigUInt(1) << 256) - 1

    static func required(_ value: String, field: String, maxLength: Int) throws -> String {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw SRC721ValidationError.emptyField(field) }
        guard result.utf8.count <= maxLength else { throw SRC721ValidationError.textTooLong(field) }
        return result
    }

    static func amount(_ value: String, field: String, allowZero: Bool = false) throws -> BigUInt {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw SRC721ValidationError.emptyField(field) }
        guard result.unicodeScalars.allSatisfy({ $0.value >= 48 && $0.value <= 57 }),
              result.first != "0" || result.count == 1,
              let amount = BigUInt(result),
              amount <= uint256Max,
              (allowZero || amount > 0) else {
            throw SRC721ValidationError.invalidAmount(field)
        }
        return amount
    }

    static func address(_ value: String, field: String, allowZero: Bool = false) throws -> Web3Core.EthereumAddress {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let address = Web3Core.EthereumAddress(result), allowZero || result.lowercased() != zeroAddress else {
            throw SRC721ValidationError.invalidAddress(field)
        }
        return address
    }

    static func baseURI(_ value: String) throws -> String {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty, result.utf8.count <= baseURIMaxUTF8Length else { throw SRC721ValidationError.invalidURL }
        guard let url = URL(string: result), let scheme = url.scheme?.lowercased(), ["https", "ipfs"].contains(scheme) else {
            throw SRC721ValidationError.invalidURL
        }
        return result
    }

    static func optionalBaseURI(_ value: String) throws -> String {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "" : try baseURI(result)
    }

    static func textInput(_ value: String, maxUTF8Length: Int) -> String {
        var result = ""
        for character in value {
            let candidate = result + String(character)
            guard candidate.utf8.count <= maxUTF8Length else { break }
            result = candidate
        }
        return result
    }

    static func decimalInput(_ value: String, maxDigits: Int = 78) -> String {
        let digits = String(value.unicodeScalars.filter { $0.value >= 48 && $0.value <= 57 })
        return String(digits.prefix(maxDigits))
    }

    static func validDecimalInput(_ value: String, maxDigits: Int = 78, maximum: BigUInt = uint256Max) -> String? {
        let digits = String(value.unicodeScalars.filter { $0.value >= 48 && $0.value <= 57 })
        guard digits.count <= maxDigits else { return nil }
        guard !digits.isEmpty else { return "" }
        let normalized = String(digits.drop(while: { $0 == "0" }))
        let canonical = normalized.isEmpty ? "0" : normalized
        guard BigUInt(canonical).map({ $0 <= maximum }) == true else { return nil }
        return canonical
    }

    static func allowListAddressesInput(_ value: String) -> String {
        String(value.unicodeScalars.filter {
            ($0.value >= 48 && $0.value <= 57) ||
            ($0.value >= 65 && $0.value <= 70) ||
            ($0.value >= 97 && $0.value <= 102) ||
            $0.value == 88 || $0.value == 120 ||
            $0.value == 44 || $0.value == 10 || $0.value == 32 || $0.value == 9
        })
    }

    static func allowListAmountsInput(_ value: String) -> String {
        var result = ""
        var current = ""

        for scalar in value.unicodeScalars {
            if scalar.value >= 48 && scalar.value <= 57 {
                current = validDecimalInput(current + String(scalar)) ?? current
            } else if scalar.value == 44 || scalar.value == 10 || scalar.value == 32 || scalar.value == 9 {
                result += current
                current = ""
                result.unicodeScalars.append(scalar)
            }
        }

        return result + current
    }

    static func logo(_ data: Data?) throws -> Data {
        guard let data, !data.isEmpty, data.count <= 128 * 1024 else { throw SRC721ValidationError.invalidLogo }
        return data
    }

    static func allowList(addresses: String, amounts: String) throws -> ([Web3Core.EthereumAddress], [BigUInt]) {
        let addressValues = addresses
            .split { $0 == "," || $0 == "\n" || $0 == " " || $0 == "\t" }
            .map(String.init)
        let amountValues = amounts
            .split { $0 == "," || $0 == "\n" || $0 == " " || $0 == "\t" }
            .map(String.init)
        guard !addressValues.isEmpty, addressValues.count == amountValues.count else {
            throw SRC721ValidationError.invalidAllowList
        }
        let parsedAddresses = try addressValues.map { try address($0, field: "safe_zone.src721.field.address".localized) }
        let parsedAmounts = try amountValues.map { try amount($0, field: "safe_zone.src721.field.amount".localized, allowZero: true) }
        return (parsedAddresses, parsedAmounts)
    }
}
