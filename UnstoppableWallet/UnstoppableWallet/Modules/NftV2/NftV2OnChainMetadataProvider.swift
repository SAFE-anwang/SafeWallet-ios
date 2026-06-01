import Alamofire
import BigInt
import EvmKit
import Foundation
import HsToolKit
import RxSwift
import MarketKit

struct NftV2OnChainAssetMetadata: Equatable {
    let nftUid: NftUid
    let name: String?
    let imageUrl: String?
    let collectionName: String?
}

final class NftV2OnChainMetadataProvider {
    private let evmBlockchainManager: EvmBlockchainManager
    private let networkManager: NetworkManager

    init(evmBlockchainManager: EvmBlockchainManager, networkManager: NetworkManager) {
        self.evmBlockchainManager = evmBlockchainManager
        self.networkManager = networkManager
    }

    func assetMetadataSingle(records: [NftRecord], account: Account, blockchainType: BlockchainType) -> Single<[NftUid: NftV2OnChainAssetMetadata]> {
        guard blockchainType.isEvm else {
            return .just([:])
        }

        guard let evmKitWrapper = try? evmBlockchainManager.evmKitManager(blockchainType: blockchainType).evmKitWrapper(account: account, blockchainType: blockchainType) else {
            return .just([:])
        }

        let evmRecords = records.compactMap { $0 as? EvmNftRecord }
        guard !evmRecords.isEmpty else {
            return .just([:])
        }

        let singles = evmRecords.map { record in
            assetMetadataSingle(record: record, evmKit: evmKitWrapper.evmKit)
                .catchErrorJustReturn(nil)
        }

        return Single.zip(singles)
            .map { entries in
                entries.reduce(into: [NftUid: NftV2OnChainAssetMetadata]()) { result, entry in
                    guard let entry else {
                        return
                    }

                    result[entry.nftUid] = entry
                }
            }
    }

    private func assetMetadataSingle(record: EvmNftRecord, evmKit: EvmKit.Kit) -> Single<NftV2OnChainAssetMetadata?> {
        guard let contractAddress = try? EvmKit.Address(hex: record.contractAddress),
              let tokenId = BigUInt(record.tokenId)
        else {
            return .just(nil)
        }

        return tokenUriSingle(record: record, contractAddress: contractAddress, tokenId: tokenId, evmKit: evmKit)
            .flatMap { [weak self] tokenUri -> Single<NftV2OnChainAssetMetadata?> in
                guard let self, let tokenUri else {
                    return .just(nil)
                }

                return self.metadataJsonSingle(tokenUri: tokenUri, tokenId: tokenId)
                    .map { json in
                        let name = Self.string(json["name"])
                        let imageUrl = Self.imageUrl(json: json, tokenId: tokenId, uniqueKey: record.nftUid.uid)
                        let collectionName = Self.collectionName(json: json) ?? record.tokenName

                        return NftV2OnChainAssetMetadata(
                            nftUid: record.nftUid,
                            name: name,
                            imageUrl: imageUrl,
                            collectionName: collectionName
                        )
                    }
                    .catchErrorJustReturn(nil)
            }
    }

    private func tokenUriSingle(record: EvmNftRecord, contractAddress: EvmKit.Address, tokenId: BigUInt, evmKit: EvmKit.Kit) -> Single<String?> {
        let method: ContractMethod

        switch record.type {
        case .eip721:
            method = NftV2TokenUriMethod(tokenId: tokenId)
        case .eip1155:
            method = NftV2UriMethod(tokenId: tokenId)
        default:
            return .just(nil)
        }

        return evmKit.call(contractAddress: contractAddress, data: method.encodedABI())
            .map { data in
                let rawUri = try Self.decodeString(data: data)
                return Self.normalizedMetadataUri(rawUri: rawUri, tokenId: tokenId)
            }
            .catchErrorJustReturn(nil)
    }

    private func metadataJsonSingle(tokenUri: String, tokenId: BigUInt) -> Single<[String: Any]> {
        if let inlineJson = Self.inlineJson(tokenUri: tokenUri) {
            return .just(inlineJson)
        }

        guard let url = URL(string: Self.normalizedResourceUrl(rawUrl: tokenUri, tokenId: tokenId)) else {
            return .error(NftV2OnChainMetadataError.invalidUrl)
        }

        let request = networkManager.session.request(url)

        return networkManager.single(request: request)
            .map { data in
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw NftV2OnChainMetadataError.invalidPayload
                }

                return object
            }
    }

    private static func normalizedMetadataUri(rawUri: String, tokenId: BigUInt) -> String {
        let trimmed = rawUri.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.contains("{id}") {
            return trimmed.replacingOccurrences(of: "{id}", with: tokenIdHex(tokenId: tokenId))
        }

        return trimmed
    }

    private static func normalizedResourceUrl(rawUrl: String, tokenId: BigUInt) -> String {
        let resolvedUrl = normalizedMetadataUri(rawUri: rawUrl, tokenId: tokenId)

        if resolvedUrl.hasPrefix("ipfs://ipfs/") {
            let path = String(resolvedUrl.dropFirst("ipfs://ipfs/".count))
            return "https://ipfs.io/ipfs/\(path)"
        }

        if resolvedUrl.hasPrefix("ipfs://") {
            let path = String(resolvedUrl.dropFirst("ipfs://".count))
            return "https://ipfs.io/ipfs/\(path)"
        }

        return resolvedUrl
    }

    private static func inlineJson(tokenUri: String) -> [String: Any]? {
        let prefix = "data:application/json;base64,"
        if tokenUri.hasPrefix(prefix) {
            let payload = String(tokenUri.dropFirst(prefix.count))
            guard let data = Data(base64Encoded: payload),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                return nil
            }

            return object
        }

        let utf8Prefix = "data:application/json;utf8,"
        if tokenUri.hasPrefix(utf8Prefix) {
            let payload = String(tokenUri.dropFirst(utf8Prefix.count)).removingPercentEncoding ?? String(tokenUri.dropFirst(utf8Prefix.count))
            guard let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                return nil
            }

            return object
        }

        return nil
    }

    private static func imageUrl(json: [String: Any], tokenId: BigUInt, uniqueKey: String) -> String? {
        if let image = string(json["image"]) {
            if let inlineImageUrl = inlineImageFileUrl(rawImage: image, tokenId: tokenId, uniqueKey: uniqueKey) {
                return inlineImageUrl
            }

            return normalizedResourceUrl(rawUrl: image, tokenId: tokenId)
        }

        if let imageUrl = string(json["image_url"]) {
            if let inlineImageUrl = inlineImageFileUrl(rawImage: imageUrl, tokenId: tokenId, uniqueKey: uniqueKey) {
                return inlineImageUrl
            }

            return normalizedResourceUrl(rawUrl: imageUrl, tokenId: tokenId)
        }

        return nil
    }

    private static func collectionName(json: [String: Any]) -> String? {
        if let collection = json["collection"] as? [String: Any],
           let name = string(collection["name"]) {
            return name
        }

        return string(json["collection_name"])
    }

    private static func string(_ value: Any?) -> String? {
        guard let string = value as? String else {
            return nil
        }

        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func tokenIdHex(tokenId: BigUInt) -> String {
        let hex = String(tokenId, radix: 16)
        return String(repeating: "0", count: max(0, 64 - hex.count)) + hex
    }

    private static func inlineImageFileUrl(rawImage: String, tokenId: BigUInt, uniqueKey: String) -> String? {
        guard rawImage.hasPrefix("data:image/"),
              let separatorIndex = rawImage.firstIndex(of: ",")
        else {
            return nil
        }

        let header = String(rawImage[..<separatorIndex])
        let payload = String(rawImage[rawImage.index(after: separatorIndex)...])

        guard header.contains(";base64"),
              let data = Data(base64Encoded: payload)
        else {
            return nil
        }

        let fileExtension: String
        if header.contains("image/svg+xml") {
            fileExtension = "svg"
        } else if header.contains("image/png") {
            fileExtension = "png"
        } else if header.contains("image/jpeg") {
            fileExtension = "jpg"
        } else if header.contains("image/webp") {
            fileExtension = "webp"
        } else {
            return nil
        }

        let safeKey = safeInlineImageKey(uniqueKey)
        let fileName = "\(safeKey)-\(tokenIdHex(tokenId: tokenId)).\(fileExtension)"
        let fileUrl = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nft-v2-inline-images", isDirectory: true)
            .appendingPathComponent(fileName)

        do {
            try FileManager.default.createDirectory(
                at: fileUrl.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileUrl, options: .atomic)
            return fileUrl.absoluteString
        } catch {
            return nil
        }
    }

    private static func safeInlineImageKey(_ key: String) -> String {
        let sanitized = key
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        if sanitized.isEmpty {
            return "nft"
        }

        return String(sanitized.prefix(80))
    }

    private static func decodeString(data: Data) throws -> String {
        guard data.count >= 64 else {
            throw NftV2OnChainMetadataError.invalidPayload
        }

        let offset = Int(BigUInt(data[0 ..< 32]))
        guard data.count >= offset + 32 else {
            throw NftV2OnChainMetadataError.invalidPayload
        }

        let length = Int(BigUInt(data[offset ..< offset + 32]))
        let start = offset + 32
        let end = start + length

        guard data.count >= end,
              let string = String(data: data[start ..< end], encoding: .utf8)
        else {
            throw NftV2OnChainMetadataError.invalidPayload
        }

        return string
    }
}

private final class NftV2TokenUriMethod: ContractMethod {
    private let tokenId: BigUInt

    init(tokenId: BigUInt) {
        self.tokenId = tokenId
        super.init()
    }

    override var methodSignature: String {
        "tokenURI(uint256)"
    }

    override var arguments: [Any] {
        [tokenId]
    }
}

private final class NftV2UriMethod: ContractMethod {
    private let tokenId: BigUInt

    init(tokenId: BigUInt) {
        self.tokenId = tokenId
        super.init()
    }

    override var methodSignature: String {
        "uri(uint256)"
    }

    override var arguments: [Any] {
        [tokenId]
    }
}

private enum NftV2OnChainMetadataError: Error {
    case invalidPayload
    case invalidUrl
}
