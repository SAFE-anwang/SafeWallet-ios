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
                t.column(Safe4NodeInfo.Columns.displayOrder.name, .integer)
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
                t.column(Safe4NodeInfo.Columns.totalVoteNum.name, .text)
                t.column(Safe4NodeInfo.Columns.totalAmount.name, .text)
                t.column(Safe4NodeInfo.Columns.allVoteNum.name, .text)
                t.primaryKey([Safe4NodeInfo.Columns.id.name, Safe4NodeInfo.Columns.recordId.name], onConflict: .replace)
            }
        }

        migrator.registerMigration("recreate Safe4NodeInfosStorage with current schema") { db in
            guard try db.tableExists(Safe4NodeInfo.databaseTableName) else { return }

            try db.drop(table: Safe4NodeInfo.databaseTableName)
            try db.create(table: Safe4NodeInfo.databaseTableName) { t in
                t.column(Safe4NodeInfo.Columns.recordId.name, .integer).notNull()
                t.column(Safe4NodeInfo.Columns.displayOrder.name, .integer)
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
                t.column(Safe4NodeInfo.Columns.totalVoteNum.name, .text)
                t.column(Safe4NodeInfo.Columns.totalAmount.name, .text)
                t.column(Safe4NodeInfo.Columns.allVoteNum.name, .text)
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
        do {
            let count = try dbPool.read { db in
                try Safe4NodeInfo.filter(Safe4NodeInfo.Columns.recordId == recordId).fetchCount(db)
            }
            print("[Safe4NodeInfoStorage] count recordId=\(recordId) count=\(count)")
            return count
        } catch {
            print("[Safe4NodeInfoStorage] count failed recordId=\(recordId) error=\(error)")
            return 0
        }
    }
    
    func fetchAllNodeInfos(recordId: Int64) -> [Safe4NodeInfo]? {
        do {
            let records = try dbPool.read { db in
                try Safe4NodeInfo
                    .filter(Safe4NodeInfo.Columns.recordId == recordId)
                    .fetchAll(db)
            }
            print("[Safe4NodeInfoStorage] fetchAll recordId=\(recordId) count=\(records.count)")
            return records
        } catch {
            print("[Safe4NodeInfoStorage] fetchAll failed recordId=\(recordId) error=\(error)")
            return nil
        }
    }
    
    func fetchNodeInfosPaginated(recordId: Int64, page: Int, pageSize: Int) -> [Safe4NodeInfo]? {
        do {
            let infos = try dbPool.read { db in
                let offset = page * pageSize
                return try Safe4NodeInfo
                    .filter(Safe4NodeInfo.Columns.recordId == recordId)
                    .limit(pageSize, offset: offset)
                    .fetchAll(db)
            }
            print("[Safe4NodeInfoStorage] fetchPage recordId=\(recordId) page=\(page) pageSize=\(pageSize) count=\(infos.count)")
            return infos
        } catch {
            print("[Safe4NodeInfoStorage] fetchPage failed recordId=\(recordId) page=\(page) pageSize=\(pageSize) error=\(error)")
            return nil
        }
    }

    @discardableResult
    func save(recordId: Int64, infos: [Safe4NodeInfo]) -> Int {
        do {
            let storedCount = try dbPool.write { db in
                let deletedCount = try Safe4NodeInfo
                    .filter(Safe4NodeInfo.Columns.recordId == recordId)
                    .deleteAll(db)
                print("[Safe4NodeInfoStorage] save begin recordId=\(recordId) incoming=\(infos.count) deleted=\(deletedCount)")

                for (index, nodeInfo) in infos.enumerated() {
                    nodeInfo.recordId = recordId
                    nodeInfo.displayOrder = index

                    do {
                        try nodeInfo.save(db)
                    } catch {
                        print("[Safe4NodeInfoStorage] insert failed recordId=\(recordId) index=\(index) id=\(nodeInfo.id) addr=\(nodeInfo.addr) error=\(error)")
                        throw error
                    }
                }

                return try Safe4NodeInfo
                    .filter(Safe4NodeInfo.Columns.recordId == recordId)
                    .fetchCount(db)
            }

            print("[Safe4NodeInfoStorage] save complete recordId=\(recordId) stored=\(storedCount)")
            return storedCount
        } catch {
            logSchema(recordId: recordId)
            print("[Safe4NodeInfoStorage] save failed recordId=\(recordId) incoming=\(infos.count) error=\(error)")
            return 0
        }
    }
    
    func deleteAllNodeInfos(recordId: Int64) {
        do {
            let deletedCount = try dbPool.write { db in
                try Safe4NodeInfo
                    .filter(Safe4NodeInfo.Columns.recordId == recordId)
                    .deleteAll(db)
            }
            print("[Safe4NodeInfoStorage] deleteAll recordId=\(recordId) deleted=\(deletedCount)")
        } catch {
            print("[Safe4NodeInfoStorage] deleteAll failed recordId=\(recordId) error=\(error)")
        }
    }

    private func logSchema(recordId: Int64) {
        do {
            let schema = try dbPool.read { db -> (String, Int) in
                let dbColumns = try db.columns(in: Safe4NodeInfo.databaseTableName)
                let columnDescriptions = dbColumns.map { column in
                    let typeDescription = String(describing: column.type)
                    return "\(column.name):\(typeDescription)"
                }
                let columns = columnDescriptions.joined(separator: ",")
                let count = try Safe4NodeInfo
                    .filter(Safe4NodeInfo.Columns.recordId == recordId)
                    .fetchCount(db)
                return (columns, count)
            }
            print("[Safe4NodeInfoStorage] schema recordId=\(recordId) columns=\(schema.0)")
            print("[Safe4NodeInfoStorage] schema count recordId=\(recordId) count=\(schema.1)")
        } catch {
            print("[Safe4NodeInfoStorage] schema failed recordId=\(recordId) error=\(error)")
        }
    }
}
