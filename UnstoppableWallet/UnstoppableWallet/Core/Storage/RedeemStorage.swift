import Foundation
import GRDB

class RedeemStorage {
    private let dbPool: DatabasePool

    init(dbPool: DatabasePool) throws {
        self.dbPool = dbPool
        try migrator.migrate(dbPool)
    }
    
    var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("create RedeemStorage") { db in
            try db.create(table: Redeem.databaseTableName) { t in
                t.column(Redeem.Columns.address.name, .text).notNull()
                t.column(Redeem.Columns.existAvailable.name, .boolean)
                t.column(Redeem.Columns.existLocked.name, .boolean)
                t.column(Redeem.Columns.existMasterNode.name, .boolean)
                t.column(Redeem.Columns.success.name, .boolean)
                t.column(Redeem.Columns.lastRedeemTimestamp.name, .double).notNull()
                
                t.primaryKey([Redeem.Columns.address.name], onConflict: .replace)
            }
        }
        return migrator
    }
}

extension RedeemStorage {
    func allRedeem()-> [Redeem] {
        try! dbPool.read { db in
            try Redeem.fetchAll(db)
        }
    }

     func save(redeem: Redeem) {
         _ = try? dbPool.write { db in
             try redeem.insert(db)
         }
    }

    func update(redeem: Redeem) {
        _ = try? dbPool.write { db in
            try redeem.update(db)
        }
   }
    
    func clear() throws {
        _ = try dbPool.write { db in
            try Redeem.deleteAll(db)
        }
    }
}
