import Foundation
import GRDB

class Safe4NodeInfoStorage {
    private let dbPool: DatabasePool

    init(dbPool: DatabasePool) throws {
        self.dbPool = dbPool
        try migrator.migrate(dbPool)
    }
    var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("create Safe4NodeInfosStorage") { db in
            try db.create(table: Safe4NodeInfo.databaseTableName) { t in
                t.column(Safe4NodeInfo.Columns.recordId.name, .integer).notNull()
                t.column(Safe4NodeInfo.Columns.id.name, .text).notNull()
                t.column(Safe4NodeInfo.Columns.name.name, .text).notNull()
                t.column(Safe4NodeInfo.Columns.addr.name, .text).notNull()
                t.column(Safe4NodeInfo.Columns.creator.name, .text).notNull()
                t.column(Safe4NodeInfo.Columns.enode.name, .text).notNull()
                t.column(Safe4NodeInfo.Columns.description.name, .text).notNull()
                t.column(Safe4NodeInfo.Columns.isOfficial.name, .boolean).notNull()
                t.column(Safe4NodeInfo.Columns.state.name, .text).notNull()
                t.column(Safe4NodeInfo.Columns.founders.name, .text).notNull()
                t.column(Safe4NodeInfo.Columns.incentivePlan.name, .text)
                t.column(Safe4NodeInfo.Columns.isUnion.name, .boolean).notNull()
                t.column(Safe4NodeInfo.Columns.lastRewardHeight.name, .text).notNull()
                t.column(Safe4NodeInfo.Columns.createHeight.name, .text).notNull()
                t.column(Safe4NodeInfo.Columns.updateHeight.name, .text).notNull()
                t.primaryKey([Safe4NodeInfo.Columns.id.name, Safe4NodeInfo.Columns.recordId.name], onConflict: .replace)
            }
        }
        
//        migrator.registerMigration("create Safe4SuperNodeStorage") { db in
//            try db.create(table: Safe4SuperNodeRecord.databaseTableName) { t in
//                t.autoIncrementedPrimaryKey(Safe4SuperNodeRecord.Columns.id.name)
//                t.column(Safe4SuperNodeRecord.Columns.totalVoteNum.name, .text).notNull()
//                t.column(Safe4SuperNodeRecord.Columns.totalAmount.name, .text).notNull()
//                t.column(Safe4SuperNodeRecord.Columns.allVoteNum.name, .text).notNull()
//                t.column(Safe4SuperNodeRecord.Columns.infoId.name, .integer)
//                    .indexed()
//                    .references("cardSettings", onDelete: .setNull)
//
////                t.autoIncrementedPrimaryKey("id")
//                t.column("title", .text).notNull()
//                t.column("headerId", .integer) // 用于关联 WordBox
//                    .indexed()
//                    .references(Safe4NodeInfo.databaseTableName, onDelete: .setNull) // 外键约束
//            }
//        }
        return migrator
    }
}

extension Safe4NodeInfoStorage {
    func totalCount(forRecordId recordId: Int64) -> Int {
        let count = try? dbPool.read { db in
            try Safe4NodeInfo.filter(Safe4NodeInfo.Columns.recordId == recordId).fetchCount(db)
        }
        return count ?? 0
    }
    
    func fetchAllNodeInfos(recordId: Int64) -> [Safe4NodeInfo]? {
        try? dbPool.read { db in
            return try Safe4NodeInfo
                .filter(Safe4NodeInfo.Columns.recordId == recordId)
                .fetchAll(db)
        }
    }
    
    func fetchNodeInfosPaginated(recordId: Int64, page: Int, pageSize: Int) -> [Safe4NodeInfo]? {
        try? dbPool.read { db in
            let offset = page * pageSize
            let infos = try Safe4NodeInfo
                .filter(Safe4NodeInfo.Columns.recordId == recordId)
                .limit(pageSize, offset: offset)
                .fetchAll(db)
            return infos
        }
    }

    func save(recordId: Int64, infos: [Safe4NodeInfo]) {
        _ = try? dbPool.write { db in
            for nodeInfo in infos {
                try? nodeInfo.insert(db)
            }
        }
    }
    
    func deleteAllNodeInfos(recordId: Int64) {
        _ = try? dbPool.write { db in
            try Safe4NodeInfo
                .filter(Safe4NodeInfo.Columns.recordId == recordId)
                .deleteAll(db)
        }
    }
}
