import Foundation
import GRDB
import web3swift

class Safe4StorageManager {
    private let databasePath: String
    private let scopeLock = NSLock()
    private var scopedManagers = [Safe4CacheScope: Safe4StorageManager]()

    /// Separate databases preserve existing record schemas while isolating IDs and deletes.
    /// The legacy unscoped database is never copied into a scoped cache.
    func scoped(_ scope: Safe4CacheScope) throws -> Safe4StorageManager {
        scopeLock.lock()
        defer { scopeLock.unlock() }
        if let manager = scopedManagers[scope] { return manager }
        let root = URL(fileURLWithPath: databasePath)
        let directory = root.deletingLastPathComponent()
            .appendingPathComponent(root.lastPathComponent + ".safe4-caches", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pool = try DatabasePool(path: directory.appendingPathComponent(scope.databaseName).path)
        let manager = try Safe4StorageManager(dbPool: pool)
        scopedManagers[scope] = manager
        return manager
    }


    let lockedRecoardStorage: Safe4LockedRecordStorage
    let withdrawLockedStorage: Safe4WithdrawLockedStorage
    let superNodeLockRecordStorage: SuperNodeLockRecordStorage
    let safe4NodeInfoStorage: Safe4NodeInfoStorage
    let proposalInfoStorage: ProposalInfoStorage
    let src20AllTokenLockedsRecordStorage: Src20AllTokenLockedRecordStorage

    init(dbPool: DatabasePool) throws {
        self.databasePath = dbPool.path
        self.lockedRecoardStorage = try Safe4LockedRecordStorage(dbPool: dbPool)
        self.withdrawLockedStorage = try Safe4WithdrawLockedStorage(dbPool: dbPool)
        self.superNodeLockRecordStorage = try SuperNodeLockRecordStorage(dbPool: dbPool)
        self.safe4NodeInfoStorage = try Safe4NodeInfoStorage(dbPool: dbPool)
        self.proposalInfoStorage = try ProposalInfoStorage(dbPool: dbPool)
        self.src20AllTokenLockedsRecordStorage = try Src20AllTokenLockedRecordStorage(dbPool: dbPool)
    }
}
