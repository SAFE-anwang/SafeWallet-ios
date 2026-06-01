import Foundation
import GRDB

class Safe4LockedRecordStorage {
    private let dbPool: DatabasePool

    init(dbPool: DatabasePool) throws {
        self.dbPool = dbPool
        try migrator.migrate(dbPool)
    }
    var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("create Safe4LockedRecordStorage") { db in
            try db.create(table: Safe4LockedRecord.databaseTableName) { t in
                t.column(Safe4LockedRecord.Columns.lockedType.name, .integer).notNull()
                t.column(Safe4LockedRecord.Columns.lockId.name, .text).notNull()
                t.column(Safe4LockedRecord.Columns.record.name, .text).notNull()
                t.column(Safe4LockedRecord.Columns.info.name, .text)
                t.primaryKey([Safe4LockedRecord.Columns.lockedType.name, Safe4LockedRecord.Columns.lockId.name], onConflict: .replace)
            }
        }
        migrator.registerMigration("recreate Safe4LockedRecordStorage with composite primary key") { db in
            guard try db.tableExists(Safe4LockedRecord.databaseTableName) else { return }
            let columns = try db.columns(in: Safe4LockedRecord.databaseTableName).map(\.name)
            guard !columns.contains(Safe4LockedRecord.Columns.lockedType.name) else { return }

            try db.drop(table: Safe4LockedRecord.databaseTableName)
            try db.create(table: Safe4LockedRecord.databaseTableName) { t in
                t.column(Safe4LockedRecord.Columns.lockedType.name, .integer).notNull()
                t.column(Safe4LockedRecord.Columns.lockId.name, .text).notNull()
                t.column(Safe4LockedRecord.Columns.record.name, .text).notNull()
                t.column(Safe4LockedRecord.Columns.info.name, .text)
                t.primaryKey([Safe4LockedRecord.Columns.lockedType.name, Safe4LockedRecord.Columns.lockId.name], onConflict: .replace)
            }
        }
        return migrator
    }
}

extension Safe4LockedRecordStorage {
    func allRecords() throws -> [Safe4LockedRecord] {
        try dbPool.read { db in
            try Safe4LockedRecord.fetchAll(db)
        }
   }
    
    func save(recoards: [Safe4LockedRecord]) {
        for recoard in recoards {
            save(recoard: recoard)
        }
    }
    
    func save(recoard: Safe4LockedRecord) {
        _ = try? dbPool.write { db in
            guard let item = try Safe4LockedRecord
                .filter(Safe4LockedRecord.Columns.lockedType == recoard.lockedType)
                .filter(Safe4LockedRecord.Columns.lockId == recoard.lockId)
                .fetchOne(db) else {
                try recoard.insert(db)
                return
            }
            item.lockedType = recoard.lockedType
            item.record = recoard.record
            item.info = recoard.info
            try item.update(db)
        }
    }
    
    func asset(type: LockedRecordSourceType, id: Int) throws -> Safe4LockedRecord? {
        try dbPool.read { db in
            try Safe4LockedRecord
                .filter(Safe4LockedRecord.Columns.lockedType == type.rawValue)
                .filter(Safe4LockedRecord.Columns.lockId == id.description)
                .fetchOne(db)
        }
    }
    
    func update(recoard: Safe4LockedRecord) {
        _ = try? dbPool.write { db in
            try recoard.update(db)
        }
   }
    
    func delete(type: LockedRecordSourceType, by id: Int) {
        _ = try? dbPool.write { db in
            try Safe4LockedRecord
                .filter(Safe4LockedRecord.Columns.lockedType == type.rawValue)
                .filter(Safe4LockedRecord.Columns.lockId == id.description)
                .deleteAll(db)
        }
    }

    func clear() throws {
        _ = try dbPool.write { db in
            try Safe4LockedRecord.deleteAll(db)
        }
    }
}
