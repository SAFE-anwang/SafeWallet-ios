import BigInt
import Foundation
import UIKit
import Web3Core
import web3swift

typealias SafeDappEthereumAddress = Web3Core.EthereumAddress

struct SafeDappViewItem: Identifiable {
    let info: DAppInfo
    var logo: UIImage?
    var logoLoaded: Bool = false

    var id: String { info.id.description }
    var keywords: [String] {
        info.keyword
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var hasLogo: Bool { logoLoaded && logo != nil }
    var logoMissing: Bool { logoLoaded && logo == nil }
    var contractAddress: String { info.contractAddr.address }
    var officialAccount: String { info.officialAccount.address }
}

struct SafeDappPublishedItem {
    let info: DAppInfo
    let logoData: Data
}

struct SafeDappFormData: Codable {
    var name = ""
    var contractAddr = ""
    var runUrl = ""
    var description = ""
    var keyword = ""
    var gitUrl = ""
    var officialUrl = ""
    var officialEmail = ""

    private enum CodingKeys: String, CodingKey {
        case name, contractAddr, runUrl, description, keyword, gitUrl, officialUrl, officialEmail
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        contractAddr = try container.decodeIfPresent(String.self, forKey: .contractAddr) ?? ""
        runUrl = try container.decodeIfPresent(String.self, forKey: .runUrl) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        keyword = try container.decodeIfPresent(String.self, forKey: .keyword) ?? ""
        gitUrl = try container.decodeIfPresent(String.self, forKey: .gitUrl) ?? ""
        officialUrl = try container.decodeIfPresent(String.self, forKey: .officialUrl) ?? ""
        officialEmail = try container.decodeIfPresent(String.self, forKey: .officialEmail) ?? ""
    }
}

enum SafeDappField: CaseIterable, Hashable, Identifiable {
    case name
    case contractAddr
    case runUrl
    case gitUrl
    case officialUrl
    case officialEmail
    case officialAccount
    case description
    case keyword

    var id: Self { self }

    static var editableFields: [SafeDappField] {
        [.name, .contractAddr, .runUrl, .description, .keyword, .gitUrl, .officialUrl, .officialEmail]
    }

    var title: String {
        switch self {
        case .name: return "safe_dapp.name".localized
        case .contractAddr: return "safe_dapp.contract_address".localized
        case .runUrl: return "safe_dapp.run_url".localized
        case .gitUrl: return "safe_dapp.git_url".localized
        case .officialUrl: return "safe_dapp.official_url".localized
        case .officialEmail: return "safe_dapp.official_email".localized
        case .officialAccount: return "safe_dapp.official_account".localized
        case .description: return "safe_dapp.description".localized
        case .keyword: return "safe_dapp.keyword".localized
        }
    }

    var prompt: String {
        switch self {
        case .name: return "safe_dapp.input.name"
        case .contractAddr: return "safe_dapp.input.contract_address"
        case .runUrl: return "safe_dapp.input.run_url"
        case .gitUrl: return "safe_dapp.input.git_url"
        case .officialUrl: return "safe_dapp.input.official_url"
        case .officialEmail: return "safe_dapp.input.official_email"
        case .officialAccount: return "safe_dapp.input.official_account"
        case .description: return "safe_dapp.input.description"
        case .keyword: return "safe_dapp.input.keyword"
        }
    }

    var maxInputCharacters: Int? {
        switch self {
        case .name: return 50
        case .runUrl, .gitUrl, .officialUrl, .keyword: return 200
        case .officialEmail: return 50
        case .description: return 1024
        case .contractAddr, .officialAccount: return nil
        }
    }

    func truncatedInput(_ value: String) -> String {
        guard let maxInputCharacters, value.count > maxInputCharacters else { return value }
        return String(value.prefix(maxInputCharacters))
    }
}

enum SafeDappAsyncState: Equatable {
    case idle
    case ready
    case sending
    case completed
    case failed(String)
}

struct SafeDappValidationError: Error, LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

enum SafeDappValidation {
    static let zeroAddress = "0x0000000000000000000000000000000000000000"

    static func characterCount(_ value: String) -> Int {
        value.count
    }

    static func validateRequired(_ value: String, min: Int, max: Int, title: String) -> String? {
        let count = characterCount(value.trimmingCharacters(in: .whitespacesAndNewlines))
        if count < min || count > max {
            return "safe_dapp.error.characters".localized(title, "\(min)", "\(max)")
        }
        return nil
    }

    static func validateOptional(_ value: String, min: Int, max: Int, title: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return validateRequired(trimmed, min: min, max: max, title: title)
    }

    static func normalizedKeyword(_ value: String, title: String) -> Result<String, SafeDappValidationError> {
        let normalized = value
            .replacingOccurrences(of: "｜", with: "|")
            .split(separator: "|", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "|")

        if let error = validateOptional(normalized, min: 0, max: 200, title: title) {
            return .failure(SafeDappValidationError(message: error))
        }
        return .success(normalized)
    }

    static func validateID(_ id: BigUInt) throws {
        guard id > 0 else {
            throw SafeDappValidationError(message: "safe_dapp.error.invalid_id".localized)
        }
    }

    static func validatePage(start: BigUInt, count: BigUInt, total: BigUInt) throws {
        guard count > 0, count <= 100, start < total else {
            throw SafeDappValidationError(message: "safe_dapp.error.invalid_page".localized)
        }
    }

    static func normalizedUrl(_ value: String, required: Bool, title: String, min: Int, max: Int) -> Result<String, SafeDappValidationError> {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty, !required {
            return .success("")
        }
        if trimmed.isEmpty, let error = validateRequired(trimmed, min: min, max: max, title: title) {
            return .failure(SafeDappValidationError(message: error))
        }
        let prepared = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard
            let url = URL(string: prepared),
            let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            let host = url.host,
            !host.isEmpty
        else {
            return .failure(SafeDappValidationError(message: "safe_dapp.error.url".localized(title)))
        }
        let normalized = url.absoluteString
        if let error = validateRequired(normalized, min: min, max: max, title: title) {
            return .failure(SafeDappValidationError(message: error))
        }
        return .success(normalized)
    }

    static func ethereumAddress(_ value: String, title: String, nonZero: Bool = true) -> Result<SafeDappEthereumAddress, SafeDappValidationError> {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let address = SafeDappEthereumAddress(trimmed) else {
            return .failure(SafeDappValidationError(message: "safe_dapp.error.address".localized(title)))
        }
        if nonZero, trimmed.lowercased() == zeroAddress {
            return .failure(SafeDappValidationError(message: "safe_dapp.error.zero_address".localized(title)))
        }
        return .success(address)
    }

    static func optionalEmail(_ value: String, title: String) -> Result<String, SafeDappValidationError> {
        email(value, required: false, title: title)
    }

    static func requiredEmail(_ value: String, title: String) -> Result<String, SafeDappValidationError> {
        email(value, required: true, title: title)
    }

    private static func email(_ value: String, required: Bool, title: String) -> Result<String, SafeDappValidationError> {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty, !required {
            return .success("")
        }
        if let error = validateRequired(trimmed, min: 5, max: 50, title: title) {
            return .failure(SafeDappValidationError(message: error))
        }
        let parts = trimmed.split(separator: "@")
        guard
            parts.count == 2,
            let domain = parts.last,
            domain.contains(".")
        else {
            return .failure(SafeDappValidationError(message: "safe_dapp.error.email".localized(title)))
        }
        return .success(trimmed)
    }

    static func validateLogo(_ logo: Data) throws {
        guard logo.count <= 128 * 1024 else {
            throw SafeDappValidationError(message: "safe_dapp.logo_oversize".localized)
        }
    }

    static func logoData(from image: UIImage) -> Data? {
        let maxBytes = 128 * 1024
        if let png = image.pngData(), png.count <= maxBytes {
            return png
        }
        var quality: CGFloat = 0.9
        while quality >= 0.2 {
            if let data = image.jpegData(compressionQuality: quality), data.count <= maxBytes {
                return data
            }
            quality -= 0.1
        }
        return nil
    }
}
