import Foundation
import HsToolKit

protocol SRC721InsightAssetProvider: AnyObject {
    func tokens() async throws -> [SRC721InsightToken]
    func holdings(owner: String) async throws -> [SRC721InsightHolding]
    func assets(owner: String, tokenAddress: String) async throws -> [SRC721InsightAsset]
}

final class SRC721InsightProvider: SRC721InsightAssetProvider {
    private let networkManager: NetworkManager
    private let chainId: Int

    init(networkManager: NetworkManager = NetworkManager(), chainId: Int) {
        self.networkManager = networkManager
        self.chainId = chainId
    }

    func tokens() async throws -> [SRC721InsightToken] {
        try await request(path: "tokens", queryItems: [])
    }

    func holdings(owner: String) async throws -> [SRC721InsightHolding] {
        try await request(path: "assets", queryItems: [URLQueryItem(name: "address", value: owner)])
    }

    func assets(owner: String, tokenAddress: String) async throws -> [SRC721InsightAsset] {
        try await request(path: "assets", queryItems: [
            URLQueryItem(name: "address", value: owner),
            URLQueryItem(name: "tokenAddress", value: tokenAddress)
        ])
    }

    private func request<T: Decodable>(path: String, queryItems: [URLQueryItem]) async throws -> T {
        let context = try Safe4Network.activeContext(chainId: chainId)
        guard var components = URLComponents(string: "\(context.apiBaseUrl)/insight/api/nft/\(path)") else {
            throw SRC721InsightError.invalidResponse
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw SRC721InsightError.invalidResponse }

        let response: SRC721InsightResponse<T> = try await networkManager.fetch(
            url: url,
            responseCacherBehavior: .doNotCache
        )
        guard response.status == "1" else {
            throw SRC721InsightError.requestFailed(response.message)
        }
        return response.result
    }
}

private struct SRC721InsightResponse<Result: Decodable>: Decodable {
    let status: String
    let message: String
    let result: Result
}

enum SRC721InsightError: LocalizedError {
    case invalidResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Unable to read Safe4 NFT data."
        case let .requestFailed(message): return message
        }
    }
}

struct SRC721InsightToken: Decodable, Equatable {
    let address: String
    let name: String
    let symbol: String
    let type: String
    let logoURI: String?
    let template: Bool
    let creator: String

    var isERC721: Bool { type.caseInsensitiveCompare("erc721") == .orderedSame }
}

struct SRC721InsightHolding: Decodable, Equatable {
    let owner: String
    let token: String
    let count: String

    private enum CodingKeys: String, CodingKey { case owner, token, count }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        owner = try container.decode(String.self, forKey: .owner)
        token = try container.decode(String.self, forKey: .token)
        count = try container.decode(SRC721InsightString.self, forKey: .count).value
    }
}

struct SRC721InsightAsset: Decodable, Equatable {
    let owner: String
    let token: String
    let tokenType: String
    let tokenId: String
    let tokenValue: String
    let tokenURI: String?
    let tokenImage: String?

    private enum CodingKeys: String, CodingKey {
        case owner, token, tokenType, tokenId, tokenValue, tokenURI, tokenImage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        owner = try container.decode(String.self, forKey: .owner)
        token = try container.decode(String.self, forKey: .token)
        tokenType = try container.decode(String.self, forKey: .tokenType)
        tokenId = try container.decode(SRC721InsightString.self, forKey: .tokenId).value
        tokenValue = try container.decode(SRC721InsightString.self, forKey: .tokenValue).value
        tokenURI = try container.decodeIfPresent(String.self, forKey: .tokenURI)
        tokenImage = try container.decodeIfPresent(String.self, forKey: .tokenImage)
    }

    var isERC721: Bool { tokenType.caseInsensitiveCompare("erc721") == .orderedSame }
}

private struct SRC721InsightString: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self.value = value
        } else if let value = try? container.decode(UInt64.self) {
            self.value = String(value)
        } else if let value = try? container.decode(Int64.self), value >= 0 {
            self.value = String(value)
        } else {
            throw DecodingError.typeMismatch(
                String.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected a non-negative integer or string")
            )
        }
    }
}
