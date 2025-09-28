import Foundation
import GRDB

class SuperNodeLockRecordStorage {
    private let dbPool: DatabasePool

    init(dbPool: DatabasePool) throws {
        self.dbPool = dbPool
        try migrator.migrate(dbPool)
    }
    var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("create SuperNodeLockRecordStorage") { db in
            try db.create(table: SuperNodeLockRecord.databaseTableName) { t in
                t.column(SuperNodeLockRecord.Columns.isSuperNode.name, .boolean).notNull()
                t.column(SuperNodeLockRecord.Columns.isVoted.name, .boolean).notNull()
                t.column(SuperNodeLockRecord.Columns.lockId.name, .text).notNull()
                t.column(SuperNodeLockRecord.Columns.record.name, .text).notNull()
                t.column(SuperNodeLockRecord.Columns.info.name, .text)
                t.primaryKey([SuperNodeLockRecord.Columns.lockId.name], onConflict: .replace)
            }
        }
        return migrator
    }
}

extension SuperNodeLockRecordStorage {
    func allRecords() throws -> [SuperNodeLockRecord] {
        try dbPool.read { db in
            try SuperNodeLockRecord.fetchAll(db)
        }
   }
    
    func save(recoards: [SuperNodeLockRecord]) {
        for recoard in recoards {
            save(recoard: recoard)
        }
    }
    
    func save(recoard: SuperNodeLockRecord) {
        _ = try? dbPool.write { db in
            guard let item = try SuperNodeLockRecord
                .filter(SuperNodeLockRecord.Columns.lockId == recoard.lockId)
                .fetchOne(db) else {
                try recoard.insert(db)
                return
            }
            try item.update(db)
        }
    }
    
    func asset(id: Int) throws -> SuperNodeLockRecord? {
        try dbPool.read { db in
            try SuperNodeLockRecord
                .filter(SuperNodeLockRecord.Columns.lockId == id.description)
                .fetchOne(db)
        }
    }
    
    func update(recoard: SuperNodeLockRecord) {
        _ = try? dbPool.write { db in
            try recoard.update(db)
        }
   }
    
    func delete(by id: Int) {
        _ = try! dbPool.write { db in
            try SuperNodeLockRecord
                .filter(SuperNodeLockRecord.Columns.lockId == id.description)
                .deleteAll(db)
        }
    }

    func clear() throws {
        _ = try dbPool.write { db in
            try SuperNodeLockRecord.deleteAll(db)
        }
    }
}

