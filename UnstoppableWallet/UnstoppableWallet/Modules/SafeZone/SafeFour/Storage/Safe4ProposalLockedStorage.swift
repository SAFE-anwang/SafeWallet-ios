import Foundation
import GRDB

class Safe4ProposalLockedStorage {
    private let dbPool: DatabasePool

    init(dbPool: DatabasePool) throws {
        self.dbPool = dbPool
        try migrator.migrate(dbPool)
    }
    var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("create Safe4ProposalLockedStorage") { db in
            try db.create(table: Safe4ProposalReward.databaseTableName) { t in
                t.column(Safe4ProposalReward.Columns.lockId.name, .text).notNull()
                t.column(Safe4ProposalReward.Columns.ids.name, .text).notNull()
                t.column(Safe4ProposalReward.Columns.info.name, .text).notNull()
                t.primaryKey([Safe4ProposalReward.Columns.lockId.name], onConflict: .replace)
            }
        }
        return migrator
    }
}

extension Safe4ProposalLockedStorage {
    
    func allRecords() throws -> [Safe4ProposalReward] {
        try dbPool.read { db in
            try Safe4ProposalReward.fetchAll(db)
        }
    }
    
    func save(records: [Safe4ProposalReward]) {
        for record in records {
            save(record: record)
        }
    }
    
    func save(record: Safe4ProposalReward) {
        _ = try? dbPool.write { db in
            guard let item = try Safe4ProposalReward
                .filter(Safe4ProposalReward.Columns.lockId == record.lockId)
                .fetchOne(db) else {
                try record.insert(db)
                return
            }
            try item.update(db)
        }
    }
    
    func asset(id: Int) throws -> Safe4ProposalReward? {
        try dbPool.read { db in
            try Safe4ProposalReward
                .filter(Safe4ProposalReward.Columns.lockId == id.description)
                .fetchOne(db)
        }
    }
    
    func update(record: Safe4ProposalReward) {
        _ = try? dbPool.write { db in
            try record.update(db)
        }
   }
    
    func delete(by id: Int) {
        _ = try! dbPool.write { db in
            try Safe4ProposalReward
                .filter(Safe4ProposalReward.Columns.lockId == id.description)
                .deleteAll(db)
        }
    }

    func clear() throws {
        _ = try dbPool.write { db in
            try Safe4ProposalReward.deleteAll(db)
        }
    }
}
