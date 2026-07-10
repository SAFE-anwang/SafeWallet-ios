import Foundation

final class NftV2FavoritesStore: ObservableObject {
    private struct Cache: Codable {
        let favoriteIds: Set<String>
    }

    @Published private(set) var favoriteIds = Set<String>()

    private let accountManager: AccountManager
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "\(AppConfig.label).nft_v2_favorites_store")
    private var cachedFavoriteIds = Set<String>()

    init(accountManager: AccountManager) {
        self.accountManager = accountManager

        syncFavorites()
    }

    func isFavorite(id: String) -> Bool {
        if Thread.isMainThread {
            return favoriteIds.contains(id)
        }

        return queue.sync {
            cachedFavoriteIds.contains(id)
        }
    }

    func toggle(id: String) {
        guard let accountId = accountManager.activeAccount?.id else {
            return
        }

        let ids = toggledIds(ids: favoriteIds, id: id)
        favoriteIds = ids

        queue.async {
            self.cachedFavoriteIds = ids
            self.save(favoriteIds: ids, accountId: accountId)
            DispatchQueue.main.async {
                guard self.accountManager.activeAccount?.id == accountId else {
                    return
                }

                self.favoriteIds = ids
            }
        }
    }

    func syncFavorites() {
        let accountId = accountManager.activeAccount?.id
        queue.async {
            let ids = accountId.flatMap(self.loadFavoriteIds(accountId:)) ?? []
            self.cachedFavoriteIds = ids

            DispatchQueue.main.async {
                guard self.accountManager.activeAccount?.id == accountId else {
                    return
                }

                self.favoriteIds = ids
            }
        }
    }

    private func toggledIds(ids: Set<String>, id: String) -> Set<String> {
        var updatedIds = ids
        if updatedIds.contains(id) {
            updatedIds.remove(id)
        } else {
            updatedIds.insert(id)
        }

        return updatedIds
    }

    private func loadFavoriteIds(accountId: String) -> Set<String> {
        guard let url = fileUrl(accountId: accountId),
              let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(Cache.self, from: data)
        else {
            return []
        }

        return cache.favoriteIds
    }

    private func save(favoriteIds: Set<String>, accountId: String) {
        guard let url = fileUrl(accountId: accountId),
              let data = try? JSONEncoder().encode(Cache(favoriteIds: favoriteIds))
        else {
            return
        }

        try? data.write(to: url, options: .atomic)
    }

    private func fileUrl(accountId: String) -> URL? {
        guard let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
        else {
            return nil
        }

        let dir = base.appendingPathComponent("nft_v2_favorites", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        return dir.appendingPathComponent("favorites_\(contextKey(accountId: accountId)).json")
    }

    private func contextKey(accountId: String) -> String {
        return accountId
            .replacingOccurrences(of: "[^a-zA-Z0-9_\\-]+", with: "_", options: .regularExpression)
    }
}
