import Foundation
import GRDB

class Safe4WithdrawLockedStorage {
    private let dbPool: DatabasePool

    init(dbPool: DatabasePool) throws {
        self.dbPool = dbPool
        try migrator.migrate(dbPool)
    }
    var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("create Safe4WithdrawLockedStorage") { db in
            try db.create(table: Safe4WithdrawLockedRecord.databaseTableName) { t in
                t.column(Safe4WithdrawLockedRecord.Columns.lockedType.name, .integer).notNull()
                t.column(Safe4WithdrawLockedRecord.Columns.lockId.name, .text).notNull()
                t.column(Safe4WithdrawLockedRecord.Columns.record.name, .text).notNull()
                t.column(Safe4WithdrawLockedRecord.Columns.info.name, .text)
                t.primaryKey([Safe4WithdrawLockedRecord.Columns.lockId.name], onConflict: .replace)
            }
        }
        return migrator
    }
}

extension Safe4WithdrawLockedStorage {
    
    func allRecords() throws -> [Safe4WithdrawLockedRecord] {
        try dbPool.read { db in
            try Safe4WithdrawLockedRecord
                .fetchAll(db)
        }
    }
    
    func allRecords(by type: LockedRecordSourceType) throws -> [Safe4WithdrawLockedRecord] {
        try dbPool.read { db in
            try Safe4WithdrawLockedRecord
                .filter(Safe4WithdrawLockedRecord.Columns.lockedType == type.rawValue)
                .fetchAll(db)
        }
    }
    
    func save(type: LockedRecordSourceType, recoards: [Safe4WithdrawLockedRecord]) {
        for recoard in recoards {
            save(type: type, recoard: recoard)
        }
    }
    
    func save(type: LockedRecordSourceType, recoard: Safe4WithdrawLockedRecord) {
        _ = try? dbPool.write { db in
            guard let item = try Safe4WithdrawLockedRecord
                .filter(Safe4WithdrawLockedRecord.Columns.lockId == recoard.lockId && Safe4WithdrawLockedRecord.Columns.lockedType == type.rawValue)
                .fetchOne(db) else {
                try recoard.insert(db)
                return
            }
            try item.update(db)
        }
    }
    
    func asset(type: LockedRecordSourceType, id: Int) throws -> Safe4WithdrawLockedRecord? {
        try dbPool.read { db in
            try Safe4WithdrawLockedRecord
                .filter(Safe4WithdrawLockedRecord.Columns.lockId == id.description && Safe4WithdrawLockedRecord.Columns.lockedType == type.rawValue)
                .fetchOne(db)
        }
    }
    
    func update(type: LockedRecordSourceType, recoard: Safe4WithdrawLockedRecord) {
        _ = try? dbPool.write { db in
            guard let recoard = try Safe4WithdrawLockedRecord
                .filter(Safe4WithdrawLockedRecord.Columns.lockId == recoard.lockId && Safe4WithdrawLockedRecord.Columns.lockedType == type.rawValue)
                .fetchOne(db) else {
                return
            }
            try recoard.update(db)
        }
   }
    
    func delete(type: LockedRecordSourceType, by id: Int) {
        _ = try! dbPool.write { db in
            try Safe4WithdrawLockedRecord
                .filter(Safe4WithdrawLockedRecord.Columns.lockId == id.description && Safe4WithdrawLockedRecord.Columns.lockedType == type.rawValue)
                .deleteAll(db)
        }
    }

    func clear(type: LockedRecordSourceType) throws {
        _ = try dbPool.write { db in
            try Safe4WithdrawLockedRecord
                .filter(Safe4WithdrawLockedRecord.Columns.lockedType == type.rawValue)
                .deleteAll(db)
        }
    }
}
