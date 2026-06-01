import Foundation

final class NftV2PendingTransferStore {
    struct Item: Codable, Hashable, Identifiable {
        let accountId: String
        let chain: String
        let collectionId: String
        let collectionName: String
        let assetId: String
        let nftUid: String
        let contractAddress: String
        let tokenId: String
        let standard: String
        let name: String
        let imageUrl: String?
        let market: String?
        let marketUrl: String?
        let balance: Int
        let canSend: Bool
        let transferType: String?
        let amount: Int
        let transactionHash: String
        let submittedAt: TimeInterval

        var id: String {
            "\(accountId)|\(chain)|\(transactionHash.lowercased())"
        }
    }

    private struct Cache: Codable {
        var items: [Item]
    }

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "\(AppConfig.label).nft_v2_pending_transfer_store")

    func items(accountId: String) -> [Item] {
        queue.sync {
            readCache(accountId: accountId)?.items ?? []
        }
    }

    func save(_ item: Item) {
        queue.sync {
            var cache = readCache(accountId: item.accountId) ?? Cache(items: [])
            cache.items.removeAll {
                $0.chain == item.chain &&
                    $0.transactionHash.caseInsensitiveCompare(item.transactionHash) == .orderedSame
            }
            cache.items.append(item)
            cache.items.sort { $0.submittedAt > $1.submittedAt }
            write(cache: cache, accountId: item.accountId)
        }
    }

    func remove(accountId: String, chain: String, transactionHash: String) {
        queue.sync {
            guard var cache = readCache(accountId: accountId) else {
                return
            }

            cache.items.removeAll {
                $0.chain == chain &&
                    $0.transactionHash.caseInsensitiveCompare(transactionHash) == .orderedSame
            }
            write(cache: cache, accountId: accountId)
        }
    }

    func clear(accountId: String) {
        queue.sync {
            guard let url = fileUrl(accountId: accountId) else {
                return
            }

            try? fileManager.removeItem(at: url)
        }
    }

    private func fileUrl(accountId: String) -> URL? {
        guard let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }

        let dir = base.appendingPathComponent("nft_v2_pending", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        return dir.appendingPathComponent("pending_\(accountId).json")
    }

    private func readCache(accountId: String) -> Cache? {
        guard let url = fileUrl(accountId: accountId),
              let data = try? Data(contentsOf: url)
        else {
            return nil
        }

        return try? JSONDecoder().decode(Cache.self, from: data)
    }

    private func write(cache: Cache, accountId: String) {
        guard let url = fileUrl(accountId: accountId),
              let data = try? JSONEncoder().encode(cache)
        else {
            return
        }

        try? data.write(to: url, options: .atomic)
    }
}
