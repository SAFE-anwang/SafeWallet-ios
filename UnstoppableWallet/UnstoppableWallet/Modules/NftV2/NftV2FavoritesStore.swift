import Foundation

final class NftV2FavoritesStore: ObservableObject {
    private struct Cache: Codable {
        let favoriteIds: Set<String>
    }

    @Published private(set) var favoriteIds = Set<String>()

    private let accountManager: AccountManager
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "\(AppConfig.label).nft_v2_favorites_store")

    init(accountManager: AccountManager) {
        self.accountManager = accountManager

        syncFavorites()
    }

    func isFavorite(id: String) -> Bool {
        favoriteIds.contains(id)
    }

    func toggle(id: String) {
        queue.sync {
            var ids = loadFavoriteIds()
            if ids.contains(id) {
                ids.remove(id)
            } else {
                ids.insert(id)
            }

            save(favoriteIds: ids)
            DispatchQueue.main.async {
                self.favoriteIds = ids
            }
        }
    }

    func syncFavorites() {
        let ids = queue.sync {
            loadFavoriteIds()
        }

        DispatchQueue.main.async {
            self.favoriteIds = ids
        }
    }

    private func loadFavoriteIds() -> Set<String> {
        guard let url = fileUrl(),
              let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(Cache.self, from: data)
        else {
            return []
        }

        return cache.favoriteIds
    }

    private func save(favoriteIds: Set<String>) {
        guard let url = fileUrl(),
              let data = try? JSONEncoder().encode(Cache(favoriteIds: favoriteIds))
        else {
            return
        }

        try? data.write(to: url, options: .atomic)
    }

    private func fileUrl() -> URL? {
        guard let account = accountManager.activeAccount,
              let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
        else {
            return nil
        }

        let dir = base.appendingPathComponent("nft_v2_favorites", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        return dir.appendingPathComponent("favorites_\(contextKey(account: account)).json")
    }

    private func contextKey(account: Account) -> String {
        return account.id
            .replacingOccurrences(of: "[^a-zA-Z0-9_\\-]+", with: "_", options: .regularExpression)
    }
}
