import Foundation
import GRDB
import web3swift

class Safe4StorageManager {
    
    let lockedRecoardStorage: Safe4LockedRecordStorage
    let withdrawLockedStorage: Safe4WithdrawLockedStorage
    let superNodeLockRecordStorage: SuperNodeLockRecordStorage
    init(dbPool: DatabasePool) throws {
        self.lockedRecoardStorage = try Safe4LockedRecordStorage(dbPool: dbPool)
        self.withdrawLockedStorage = try Safe4WithdrawLockedStorage(dbPool: dbPool)
        self.superNodeLockRecordStorage = try SuperNodeLockRecordStorage(dbPool: dbPool)
    }
}
