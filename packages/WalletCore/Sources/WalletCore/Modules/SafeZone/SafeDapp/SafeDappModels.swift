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

struct SafeDappFormData {
    var name = ""
    var contractAddr = ""
    var runUrl = ""
    var description = ""
    var gitUrl = ""
    var officialUrl = ""
    var officialEmail = ""
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

    static func utf8Count(_ value: String) -> Int {
        value.data(using: .utf8)?.count ?? 0
    }

    static func validateRequired(_ value: String, min: Int, max: Int, title: String) -> String? {
        let count = utf8Count(value.trimmingCharacters(in: .whitespacesAndNewlines))
        if count < min || count > max {
            return "safe_dapp.error.bytes".localized(title, "\(min)", "\(max)")
        }
        return nil
    }

    static func validateOptional(_ value: String, min: Int, max: Int, title: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return validateRequired(trimmed, min: min, max: max, title: title)
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
