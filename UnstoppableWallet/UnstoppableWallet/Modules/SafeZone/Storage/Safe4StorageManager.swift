import Foundation
import GRDB
import web3swift

class Safe4StorageManager {
    
    let lockedRecoardStorage: Safe4LockedRecordStorage
    let withdrawLockedStorage: Safe4WithdrawLockedStorage
    let superNodeLockRecordStorage: SuperNodeLockRecordStorage
    let safe4NodeInfoStorage: Safe4NodeInfoStorage
    let proposalInfoStorage: ProposalInfoStorage
    init(dbPool: DatabasePool) throws {
        self.lockedRecoardStorage = try Safe4LockedRecordStorage(dbPool: dbPool)
        self.withdrawLockedStorage = try Safe4WithdrawLockedStorage(dbPool: dbPool)
        self.superNodeLockRecordStorage = try SuperNodeLockRecordStorage(dbPool: dbPool)
        self.safe4NodeInfoStorage = try Safe4NodeInfoStorage(dbPool: dbPool)
        self.proposalInfoStorage = try ProposalInfoStorage(dbPool: dbPool)
    }
}
