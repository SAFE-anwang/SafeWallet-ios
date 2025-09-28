import Foundation
import GRDB

class Safe4WithdrawProposalStorage {
    private let dbPool: DatabasePool

    init(dbPool: DatabasePool) throws {
        self.dbPool = dbPool
        try migrator.migrate(dbPool)
    }
    var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("create Safe4WithdrawProposalStorage") { db in
            try db.create(table: Safe4WithdrawProposalReward.databaseTableName) { t in
                t.column(Safe4WithdrawProposalReward.Columns.lockId.name, .text).notNull()
                t.column(Safe4WithdrawProposalReward.Columns.ids.name, .text).notNull()
                t.column(Safe4WithdrawProposalReward.Columns.info.name, .text).notNull()
                t.primaryKey([Safe4WithdrawProposalReward.Columns.lockId.name], onConflict: .replace)
            }
        }
        return migrator
    }
}

extension Safe4WithdrawProposalStorage {
    func allRecords() throws -> [Safe4WithdrawProposalReward] {
        try dbPool.read { db in
            try Safe4WithdrawProposalReward.fetchAll(db)
        }
    }
    
    func save(records: [Safe4WithdrawProposalReward]) {
        for record in records {
            save(record: record)
        }
    }
    
    func save(record: Safe4WithdrawProposalReward) {
        _ = try? dbPool.write { db in
            guard let item = try Safe4WithdrawProposalReward
                .filter(Safe4WithdrawProposalReward.Columns.lockId == record.lockId)
                .fetchOne(db) else {
                try record.insert(db)
                return
            }
            try item.update(db)
        }
    }
    
    func asset(id: Int) throws -> Safe4WithdrawProposalReward? {
        try dbPool.read { db in
            try Safe4WithdrawProposalReward
                .filter(Safe4WithdrawProposalReward.Columns.lockId == id.description)
                .fetchOne(db)
        }
    }
    
    func update(record: Safe4WithdrawProposalReward) {
        _ = try? dbPool.write { db in
            try record.update(db)
        }
   }
    
    func delete(by id: Int) {
        _ = try! dbPool.write { db in
            try Safe4WithdrawProposalReward
                .filter(Safe4WithdrawProposalReward.Columns.lockId == id.description)
                .deleteAll(db)
        }
    }

    func clear() throws {
        _ = try dbPool.write { db in
            try Safe4WithdrawProposalReward.deleteAll(db)
        }
    }
}
