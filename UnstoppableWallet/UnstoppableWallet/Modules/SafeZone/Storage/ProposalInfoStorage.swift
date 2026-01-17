import Foundation
import GRDB

class ProposalInfoStorage {
    private let dbPool: DatabasePool

    init(dbPool: DatabasePool) throws {
        self.dbPool = dbPool
        try migrator.migrate(dbPool)
    }
    var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("create Safe4ProposalInfoStorage") { db in
            try db.create(table: ProposalInfoRecord.databaseTableName) { t in
                t.column(ProposalInfoRecord.Columns.id.name, .integer).notNull()
                t.column(ProposalInfoRecord.Columns.creator.name, .text).notNull()
                t.column(ProposalInfoRecord.Columns.title.name, .text).notNull()
                t.column(ProposalInfoRecord.Columns.payAmount.name, .text).notNull()
                t.column(ProposalInfoRecord.Columns.payTimes.name, .text).notNull()
                t.column(ProposalInfoRecord.Columns.startPayTime.name, .text).notNull()
                t.column(ProposalInfoRecord.Columns.endPayTime.name, .text).notNull()
                t.column(ProposalInfoRecord.Columns.description.name, .boolean).notNull()
                t.column(ProposalInfoRecord.Columns.state.name, .text).notNull()
                t.column(ProposalInfoRecord.Columns.createHeight.name, .text).notNull()
                t.column(ProposalInfoRecord.Columns.updateHeight.name, .text)
                t.primaryKey([ProposalInfoRecord.Columns.id.name], onConflict: .replace)
            }
        }
        return migrator
    }
}

extension ProposalInfoStorage {
    func countAll() -> Int? {
        return try? dbPool.read { db in
            try ProposalInfoRecord.fetchCount(db)
        }
    }
    
    func save(records: [ProposalInfoRecord]) {
        try? dbPool.write { db in
            for record in records {
                try record.save(db)
            }
        }
    }
    
    func deleteAll() {
        _ = try? dbPool.write { db in
            try ProposalInfoRecord.deleteAll(db)
        }
    }
    func fetchAllRecords() -> [ProposalInfoRecord]? {
        try? dbPool.read { db in
            let infos = try ProposalInfoRecord
                .fetchAll(db)
            return infos
        }
    }
        
    func fetchRecords(offset: Int, pageSize: Int) -> [ProposalInfoRecord]? {
        try? dbPool.read { db in
            let infos = try ProposalInfoRecord
                .limit(pageSize, offset: offset)
                .fetchAll(db)
            return infos
        }
    }
}
