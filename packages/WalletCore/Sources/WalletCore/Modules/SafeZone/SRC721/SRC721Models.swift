import BigInt
import Foundation
import Web3Core

enum SRC721ContractType: String, CaseIterable, Codable, Hashable, Identifiable {
    case standard
    case burnable
    case generic
    case unknown

    var id: Self { self }

    var title: String {
        switch self {
        case .standard: return "safe_zone.src721.type.standard".localized
        case .burnable: return "safe_zone.src721.type.burnable".localized
        case .generic: return "safe_zone.src721.type.generic".localized
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

enum SRC721TransactionOperation: String, Codable, Hashable {
    case transfer
    case burn
}

struct SRC721BatchOperationError: LocalizedError {
    let submittedHashes: [String]
    let underlying: Error

    init(submittedHashes: [String], underlying: Error) {
        self.submittedHashes = submittedHashes
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

    var isInsightDiscovered: Bool { validationStatus == "insight" }

    static func insightDiscoveredRecords(
        from tokens: [SRC721InsightToken],
        accountId: String,
        chainId: Int,
        walletAddress: String
    ) -> [SRC721ContractRecord] {
        guard let normalizedWalletAddress = Web3Core.EthereumAddress(walletAddress)?.address else {
            return []
        }

        var recordsByAddress: [String: SRC721ContractRecord] = [:]
        for token in tokens where token.isERC721 {
            guard let contractAddress = Web3Core.EthereumAddress(token.address)?.address,
                  let creatorAddress = Web3Core.EthereumAddress(token.creator)?.address,
                  creatorAddress.caseInsensitiveCompare(normalizedWalletAddress) == .orderedSame else {
                continue
            }

            let record = SRC721ContractRecord(
                accountId: accountId,
                chainId: chainId,
                walletAddress: normalizedWalletAddress,
                contractAddress: contractAddress,
                predictedContractAddress: nil,
                creatorAddress: creatorAddress,
                currentOwnerAddress: nil,
                contractType: token.src721ContractType,
                name: token.name,
                symbol: token.symbol,
                baseURI: "",
                maxSupply: "0",
                mintPrice: "0",
                deployTransactionHash: nil,
                transactionStatus: .confirmed,
                validationStatus: "insight",
                createdAt: Date(timeIntervalSince1970: 0)
            )
            if recordsByAddress[contractAddress.lowercased()] == nil {
                recordsByAddress[contractAddress.lowercased()] = record
            }
        }

        return recordsByAddress.values.sorted {
            $0.contractAddress.localizedCaseInsensitiveCompare($1.contractAddress) == .orderedAscending
        }
    }

    static func merging(
        localRecords: [SRC721ContractRecord],
        discoveredRecords: [SRC721ContractRecord]
    ) -> [SRC721ContractRecord] {
        var recordsByAddress = Dictionary(
            localRecords.map { (normalizedAddress($0.contractAddress), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for record in discoveredRecords {
            let key = normalizedAddress(record.contractAddress)
            if recordsByAddress[key] == nil {
                recordsByAddress[key] = record
            }
        }

        return recordsByAddress.values.sorted {
            if $0.createdAt != $1.createdAt {
                return $0.createdAt > $1.createdAt
            }
            return $0.contractAddress.localizedCaseInsensitiveCompare($1.contractAddress) == .orderedAscending
        }
    }

    private static func normalizedAddress(_ value: String) -> String {
        Web3Core.EthereumAddress(value)?.address.lowercased() ?? value.lowercased()
    }
}

struct SRC721ContractState: Equatable {
    let name: String
    let symbol: String
    let ownerAddress: String
    let baseURI: String
    let maxSupply: BigUInt
    let totalSupply: BigUInt
    let burnedCount: BigUInt?
    let remainSupply: BigUInt
    let mintPrice: BigUInt
    let orgName: String
    let description: String
    let officialURL: String
    let whitePaperURL: String
    let logo: Data

    var isSoldOut: Bool { remainSupply == 0 }
    static func burnedCount(mintedTotal: BigUInt?, totalSupply: BigUInt) -> BigUInt? {
        guard let mintedTotal, mintedTotal >= totalSupply else { return nil }
        return mintedTotal - totalSupply
    }
}

struct SRC721ContractSupplyState: Equatable {
    let totalSupply: BigUInt
    let burnedCount: BigUInt?
    let remainSupply: BigUInt
}

struct SRC721TokenState: Equatable {
    let tokenId: BigUInt
    let ownerAddress: String
    let approvedAddress: String
    let isApprovedForAll: Bool
    let tokenURI: String?
}

struct SRC721TokenAuthorization: Equatable {
    let tokenId: BigUInt
    let ownerAddress: String
    let approvedAddress: String
    let isApprovedForAll: Bool
}

enum SRC721AssetSource: String, Equatable {
    case onChain
    case indexer
}

struct SRC721OwnedToken: Identifiable, Equatable {
    let tokenId: BigUInt
    let ownerAddress: String
    let tokenURI: String?
    let imageURL: String?
    let source: SRC721AssetSource

    var id: String { tokenId.description }

    init(tokenId: BigUInt, ownerAddress: String, tokenURI: String?, imageURL: String? = nil, source: SRC721AssetSource) {
        self.tokenId = tokenId
        self.ownerAddress = ownerAddress
        self.tokenURI = tokenURI
        self.imageURL = imageURL
        self.source = source
    }
}

struct SRC721OwnedTokenPage: Equatable {
    let total: BigUInt
    let tokens: [SRC721OwnedToken]
    let supportsEnumeration: Bool
}

struct SRC721WalletAsset: Identifiable, Equatable {
    let contract: SRC721ContractRecord
    let token: SRC721OwnedToken
    let pendingOperation: SRC721TransactionOperation?

    init(contract: SRC721ContractRecord, token: SRC721OwnedToken, pendingOperation: SRC721TransactionOperation? = nil) {
        self.contract = contract
        self.token = token
        self.pendingOperation = pendingOperation
    }

    var id: String { "\(contract.id):\(token.id)" }
}

struct SRC721WalletCollection: Identifiable, Equatable {
    let contract: SRC721ContractRecord
    let assets: [SRC721WalletAsset]

    var id: String { contract.id }
    var displayName: String { contract.name.isEmpty ? "SRC721" : contract.name }

    static func grouped(assets: [SRC721WalletAsset]) -> [SRC721WalletCollection] {
        let collections = Dictionary(grouping: assets, by: { $0.contract.id }).map { _, assets in
            SRC721WalletCollection(
                contract: assets[0].contract,
                assets: assets.sorted { $0.token.tokenId < $1.token.tokenId }
            )
        }

        return collections.sorted {
            let result = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
            if result == .orderedSame {
                return $0.contract.contractAddress.localizedCaseInsensitiveCompare($1.contract.contractAddress) == .orderedAscending
            }
            return result == .orderedAscending
        }
    }
}

struct SRC721AllowListEntry: Codable, Hashable, Identifiable {
    let accountId: String
    let chainId: Int
    let walletAddress: String
    let contractAddress: String
    let address: String
    let amount: String
    let transactionHash: String
    let updatedAt: Date

    var id: String {
        "\(accountId):\(chainId):\(walletAddress.lowercased()):\(contractAddress.lowercased()):\(address.lowercased())"
    }
}

enum SRC721AllowListEditorField: Hashable {
    case address, amount
}

enum SRC721OwnedTokenPaging {
    static func hasMore(offset: Int, total: BigUInt) -> Bool {
        offset >= 0 && BigUInt(offset) < total
    }

    static func nextOffset(offset: Int, total: BigUInt, returnedCount: Int, limit: Int) throws -> Int {
        guard offset >= 0, limit > 0, returnedCount >= 0, returnedCount <= limit else {
            throw SRC721ValidationError.enumerationUnavailable
        }

        let offsetValue = BigUInt(offset)
        let returnedValue = BigUInt(returnedCount)
        guard offsetValue <= total, returnedValue <= total - offsetValue else {
            throw SRC721ValidationError.enumerationUnavailable
        }
        guard returnedCount > 0 || offsetValue == total else {
            throw SRC721ValidationError.enumerationUnavailable
        }
        guard returnedCount <= Int.max - offset else {
            throw SRC721ValidationError.enumerationUnavailable
        }
        return offset + returnedCount
    }
}

protocol SRC721OwnedAssetProvider {
    func ownedTokenPage(type: SRC721ContractType, offset: Int, limit: Int) async throws -> SRC721OwnedTokenPage
}

struct SRC721AllowListPage {
    static let maximumCount = 100

    let start: BigUInt
    let total: BigUInt
    let entries: [(address: String, amount: BigUInt)]

    var nextStart: BigUInt { start + BigUInt(entries.count) }
    var hasMore: Bool { nextStart < total }

    static func nextStart(start: BigUInt, total: BigUInt, returnedCount: Int) throws -> BigUInt {
        guard start <= total,
              returnedCount > 0,
              BigUInt(returnedCount) <= total - start else {
            throw SRC721ValidationError.invalidAllowList
        }
        return start + BigUInt(returnedCount)
    }
}

struct SRC721TransactionRecord: Codable, Hashable, Identifiable {
    let id: UUID
    let accountId: String
    let chainId: Int
    let walletAddress: String
    let contractAddress: String
    let operation: String
    let operationKind: SRC721TransactionOperation?
    let tokenId: String?
    let transactionHash: String
    var status: SRC721TransactionStatus
    var errorMessage: String?
    let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, accountId, chainId, walletAddress, contractAddress, operation, operationKind, tokenId
        case transactionHash, status, errorMessage, createdAt
    }

    init(
        id: UUID,
        accountId: String,
        chainId: Int,
        walletAddress: String,
        contractAddress: String,
        operation: String,
        operationKind: SRC721TransactionOperation? = nil,
        tokenId: String?,
        transactionHash: String,
        status: SRC721TransactionStatus,
        errorMessage: String?,
        createdAt: Date
    ) {
        self.id = id
        self.accountId = accountId
        self.chainId = chainId
        self.walletAddress = walletAddress
        self.contractAddress = contractAddress
        self.operation = operation
        self.operationKind = operationKind
        self.tokenId = tokenId
        self.transactionHash = transactionHash
        self.status = status
        self.errorMessage = errorMessage
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        accountId = try container.decode(String.self, forKey: .accountId)
        chainId = try container.decode(Int.self, forKey: .chainId)
        walletAddress = try container.decode(String.self, forKey: .walletAddress)
        contractAddress = try container.decode(String.self, forKey: .contractAddress)
        operation = try container.decode(String.self, forKey: .operation)
        operationKind = try container.decodeIfPresent(SRC721TransactionOperation.self, forKey: .operationKind)
        tokenId = try container.decodeIfPresent(String.self, forKey: .tokenId)
        transactionHash = try container.decode(String.self, forKey: .transactionHash)
        status = try container.decode(SRC721TransactionStatus.self, forKey: .status)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    var tokenOperation: SRC721TransactionOperation? {
        if let operationKind {
            return operationKind
        }
        if operation == "safe_zone.src721.action.transfer".localized {
            return .transfer
        }
        if operation == "safe_zone.src721.action.burn".localized {
            return .burn
        }
        return nil
    }
}

enum SRC721ValidationError: LocalizedError {
    case missingAccount
    case invalidAddress(String)
    case invalidAmount(String)
    case invalidURL
    case invalidAllowList
    case allowListUnavailable
    case allowListReadFailed(String)
    case duplicateAllowListAddress
    case invalidTokenId
    case invalidLogo
    case emptyField(String)
    case textTooLong(String)
    case invalidContract
    case enumerationUnavailable
    case tokenOperationUnavailable
    case ownerRequired
    case contractStateUnavailable
    case publicMintUnavailable
    case publicMintAllowanceInsufficient
    case supplyInsufficient
    case insufficientLogoBalance
    case transactionTimeout
    case missingSigner

    var errorDescription: String? {
        switch self {
        case .missingAccount: return "safe_zone.src721.error.account".localized
        case let .invalidAddress(field): return "safe_zone.src721.error.address".localized(field)
        case let .invalidAmount(field): return "safe_zone.src721.error.amount".localized(field)
        case .invalidURL: return "safe_zone.src721.error.url".localized
        case .invalidAllowList: return "safe_zone.src721.error.allow_list".localized
        case .allowListUnavailable: return "safe_zone.src721.error.allow_list_unavailable".localized
        case let .allowListReadFailed(message): return "safe_zone.src721.error.allow_list_read_failed".localized(message)
        case .duplicateAllowListAddress: return "safe_zone.src721.error.allow_list_duplicate".localized
        case .invalidTokenId: return "safe_zone.src721.error.token_id".localized
        case .invalidLogo: return "safe_zone.src721.error.logo".localized
        case let .emptyField(field): return "safe_zone.src721.error.required".localized(field)
        case let .textTooLong(field): return "safe_zone.src721.error.too_long".localized(field)
        case .invalidContract: return "safe_zone.src721.error.contract".localized
        case .enumerationUnavailable: return "safe_zone.src721.error.enumeration_unavailable".localized
        case .tokenOperationUnavailable: return "safe_zone.src721.error.token_operation_unavailable".localized
        case .ownerRequired: return "safe_zone.src721.error.owner_required".localized
        case .contractStateUnavailable: return "safe_zone.src721.error.contract_state_unavailable".localized
        case .publicMintUnavailable: return "safe_zone.src721.error.public_mint_unavailable".localized
        case .publicMintAllowanceInsufficient: return "safe_zone.src721.error.public_mint_allowance".localized
        case .supplyInsufficient: return "safe_zone.src721.error.supply_insufficient".localized
        case .insufficientLogoBalance: return "safe_zone.src721.error.insufficient_logo_balance".localized
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

    static func validateLogoBalance(balance: BigUInt, required: BigUInt) throws {
        guard balance >= required else { throw SRC721ValidationError.insufficientLogoBalance }
    }

    static func isInsufficientFundsError(_ message: String) -> Bool {
        let description = message.lowercased()
        return description.contains("insufficient funds") ||
            description.contains("insufficient balance") ||
            description.contains("gas required exceeds allowance")
    }

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

    static func validateMintSupply(remainSupply: BigUInt, amount: BigUInt) throws {
        guard remainSupply >= amount else { throw SRC721ValidationError.supplyInsufficient }
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
        guard let url = URL(string: result), let scheme = url.scheme?.lowercased(), ["http", "https", "ipfs"].contains(scheme) else {
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
