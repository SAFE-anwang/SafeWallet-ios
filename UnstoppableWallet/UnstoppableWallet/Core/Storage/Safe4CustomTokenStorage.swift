import Foundation
import GRDB

class Safe4CustomTokenStorage {
    private let dbPool: DatabasePool

    init(dbPool: DatabasePool) throws {
        self.dbPool = dbPool
        try migrator.migrate(dbPool)
    }
    
    var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("create Safe4CustomTokenStorage") { db in
            try db.create(table: Safe4CustomTokenRecord.databaseTableName) { t in
                t.column(Safe4CustomTokenRecord.Columns.address.name, .text).notNull()
                t.column(Safe4CustomTokenRecord.Columns.symbol.name, .text).notNull()
                t.column(Safe4CustomTokenRecord.Columns.creator.name, .text).notNull()
                t.column(Safe4CustomTokenRecord.Columns.chainId.name, .integer).notNull()
                t.column(Safe4CustomTokenRecord.Columns.decimals.name, .integer).notNull()
                t.column(Safe4CustomTokenRecord.Columns.name.name, .text).notNull()
                t.column(Safe4CustomTokenRecord.Columns.type.name, .integer)
                t.column(Safe4CustomTokenRecord.Columns.logoURI.name, .text)
                t.column(Safe4CustomTokenRecord.Columns.version.name, .text)
                
                t.primaryKey([Redeem.Columns.address.name], onConflict: .replace)
            }
        }
        return migrator
    }
}

extension Safe4CustomTokenStorage {
    func allTokens() -> [Safe4CustomTokenRecord] {
        try! dbPool.read { db in
            try Safe4CustomTokenRecord.fetchAll(db)
        }
    }
    
    func save(tokens: [Safe4CustomTokenRecord]) {
        for token in tokens {
            save(token: token)
        }
    }
    
    func save(token: Safe4CustomTokenRecord) {
        _ = try? dbPool.write { db in
            guard let record = try Safe4CustomTokenRecord
                .filter(Safe4CustomTokenRecord.Columns.address == token.address)
                .fetchOne(db) else {
                try token.insert(db)
                return
            }
            try record.update(db)
        }
    }
    
    func asset(address: String) throws -> Safe4CustomTokenRecord? {
        try dbPool.read { db in
            try Safe4CustomTokenRecord
                .filter(Safe4CustomTokenRecord.Columns.address == address)
                .fetchOne(db)
        }
    }
    
    func update(token: Safe4CustomTokenRecord) {
        _ = try? dbPool.write { db in
            try token.update(db)
        }
   }
    
    func update(logo: String, address: String) {
        _ = try? dbPool.write { db in
            guard let record = try Safe4CustomTokenRecord
                .filter(Safe4CustomTokenRecord.Columns.address == address)
                .fetchOne(db) else {
                return
            }
            record.logoURI = logo
            try record.update(db)
        }
   }
    
    func delete(by address: String) {
        _ = try! dbPool.write { db in
            try Safe4CustomTokenRecord
                .filter(Safe4CustomTokenRecord.Columns.address == address)
                .deleteAll(db)
        }
    }

    func clear() throws {
        _ = try dbPool.write { db in
            try Safe4CustomTokenRecord.deleteAll(db)
        }
    }
}
