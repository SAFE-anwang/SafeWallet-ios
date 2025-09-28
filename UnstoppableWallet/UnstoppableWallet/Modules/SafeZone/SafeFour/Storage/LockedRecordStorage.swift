
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
        migrator.registerMigration("create Safe4Safe4LockedRecordStorage") { db in
            try db.create(table: Safe4LockedRecord.databaseTableName) { t in
                t.column(Safe4LockedRecord.Columns.lockId.name, .text).notNull()
                t.column(Safe4LockedRecord.Columns.record.name, .text).notNull()
                t.column(Safe4LockedRecord.Columns.info.name, .text)
                t.primaryKey([Safe4LockedRecord.Columns.lockId.name], onConflict: .replace)
            }
        }
        return migrator
    }
}

extension Safe4LockedRecordStorage {
    func allRecords()-> [Safe4LockedRecord] {
        try! dbPool.read { db in
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
                .filter(Safe4LockedRecord.Columns.lockId == recoard.lockId)
                .fetchOne(db) else {
                try recoard.insert(db)
                return
            }
            try item.update(db)
        }
    }
    
    func asset(id: Int) throws -> Safe4LockedRecord? {
        try dbPool.read { db in
            try Safe4LockedRecord
                .filter(Safe4LockedRecord.Columns.lockId == id.description)
                .fetchOne(db)
        }
    }
    
    func update(recoard: Safe4LockedRecord) {
        _ = try? dbPool.write { db in
            try recoard.update(db)
        }
   }
    
    func delete(by id: Int) {
        _ = try! dbPool.write { db in
            try Safe4LockedRecord
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
