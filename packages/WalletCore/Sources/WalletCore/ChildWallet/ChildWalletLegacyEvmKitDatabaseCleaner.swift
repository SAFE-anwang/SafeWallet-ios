import Foundation

final class ChildWalletLegacyEvmKitDatabaseCleaner {
    private let directoryURLProviders: [() throws -> URL]
    private let queue = DispatchQueue(label: "\(AppConfig.label).child-wallet-legacy-evm-kit-db-cleaner")
    private var cleanedParentAccountIds = Set<String>()
    private var cleanedAllLegacyDatabases = false

    init(directoryURLProvider: @escaping () throws -> URL) {
        directoryURLProviders = [directoryURLProvider]
    }

    init(directoryURLProviders: [() throws -> URL] = ChildWalletLegacyEvmKitDatabaseCleaner.defaultKitDirectoryURLProviders) {
        self.directoryURLProviders = directoryURLProviders
    }

    static var defaultKitDirectoryURLProviders: [() throws -> URL] {
        [
            defaultEthereumKitDirectoryURL,
            defaultTronKitDirectoryURL,
        ]
    }

    static func defaultEthereumKitDirectoryURL() throws -> URL {
        try applicationSupportDirectoryURL().appendingPathComponent("ethereum-kit", isDirectory: true)
    }

    static func defaultTronKitDirectoryURL() throws -> URL {
        try applicationSupportDirectoryURL().appendingPathComponent("tron-kit", isDirectory: true)
    }

    private static func applicationSupportDirectoryURL() throws -> URL {
        let url = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)

        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    func cleanLegacyChildWalletDatabases(parentAccountId: String) throws -> Int {
        try queue.sync {
            guard !cleanedParentAccountIds.contains(parentAccountId) else {
                return 0
            }

            let legacyComponent = "\(parentAccountId):child:"
            let removedCount = try removeLegacyDatabases { $0.contains(legacyComponent) }
            cleanedParentAccountIds.insert(parentAccountId)
            return removedCount
        }
    }

    @discardableResult
    func cleanAllLegacyChildWalletDatabases() throws -> Int {
        try queue.sync {
            guard !cleanedAllLegacyDatabases else {
                return 0
            }

            let removedCount = try removeLegacyDatabases { $0.contains(":child:") }
            cleanedAllLegacyDatabases = true
            return removedCount
        }
    }

    private func removeLegacyDatabases(matching predicate: (String) -> Bool) throws -> Int {
        var removedCount = 0
        for directoryURLProvider in directoryURLProviders {
            let directoryURL = try directoryURLProvider()
            guard FileManager.default.fileExists(atPath: directoryURL.path) else {
                continue
            }

            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )

            for fileURL in fileURLs where predicate(fileURL.lastPathComponent) {
                try FileManager.default.removeItem(at: fileURL)
                removedCount += 1
            }
        }

        return removedCount
    }
}
