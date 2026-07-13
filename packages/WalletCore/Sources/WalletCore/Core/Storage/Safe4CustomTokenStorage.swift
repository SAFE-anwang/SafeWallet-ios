import Foundation
import GRDB
import EvmKit

class Safe4CustomTokenStorage {
    private let dbPool: DatabasePool
    private var currentChainId: Int { Safe4Network.currentChainId }

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

                t.primaryKey([Safe4CustomTokenRecord.Columns.address.name, Safe4CustomTokenRecord.Columns.chainId.name], onConflict: .replace)
            }
        }
        migrator.registerMigration("safe4 custom token chain primary key") { db in
            let tableName = Safe4CustomTokenRecord.databaseTableName
            let tempTableName = "\(tableName)_v2"

            try db.create(table: tempTableName) { t in
                t.column(Safe4CustomTokenRecord.Columns.address.name, .text).notNull()
                t.column(Safe4CustomTokenRecord.Columns.symbol.name, .text).notNull()
                t.column(Safe4CustomTokenRecord.Columns.creator.name, .text).notNull()
                t.column(Safe4CustomTokenRecord.Columns.chainId.name, .integer).notNull()
                t.column(Safe4CustomTokenRecord.Columns.decimals.name, .integer).notNull()
                t.column(Safe4CustomTokenRecord.Columns.name.name, .text).notNull()
                t.column(Safe4CustomTokenRecord.Columns.type.name, .integer)
                t.column(Safe4CustomTokenRecord.Columns.logoURI.name, .text)
                t.column(Safe4CustomTokenRecord.Columns.version.name, .text)

                t.primaryKey([Safe4CustomTokenRecord.Columns.address.name, Safe4CustomTokenRecord.Columns.chainId.name], onConflict: .replace)
            }

            try db.execute(sql: """
                INSERT OR REPLACE INTO \(tempTableName) (address, symbol, creator, chainId, decimals, name, type, logoURI, version)
                SELECT address, symbol, creator, chainId, decimals, name, type, logoURI, version FROM \(tableName)
                """)
            try db.drop(table: tableName)
            try db.execute(sql: "ALTER TABLE \(tempTableName) RENAME TO \(tableName)")
        }
        return migrator
    }
}

extension Safe4CustomTokenStorage {
    func allTokens() -> [Safe4CustomTokenRecord] {
        allTokens(chainId: currentChainId)
    }

    func allTokens(chainId: Int) -> [Safe4CustomTokenRecord] {
        try! dbPool.read { db in
            try Safe4CustomTokenRecord
                .filter(Safe4CustomTokenRecord.Columns.chainId == chainId)
                .fetchAll(db)
        }
    }

    func save(tokens: [Safe4CustomTokenRecord]) {
        for token in tokens {
            save(token: token)
        }
    }

    func save(token: Safe4CustomTokenRecord) {
        _ = try? dbPool.write { db in
            try token.save(db)
        }
    }

    func asset(address: String) throws -> Safe4CustomTokenRecord? {
        try asset(address: address, chainId: currentChainId)
    }

    func asset(address: String, chainId: Int) throws -> Safe4CustomTokenRecord? {
        try dbPool.read { db in
            try Safe4CustomTokenRecord
                .filter(Safe4CustomTokenRecord.Columns.address.lowercased == address.lowercased())
                .filter(Safe4CustomTokenRecord.Columns.chainId == chainId)
                .fetchOne(db)
        }
    }

    func update(token: Safe4CustomTokenRecord) {
        _ = try? dbPool.write { db in
            try token.update(db)
        }
   }

    func update(logo: String, address: String) {
        update(logo: logo, address: address, chainId: currentChainId)
    }

    func update(logo: String, address: String, chainId: Int) {
        _ = try? dbPool.write { db in
            guard let record = try Safe4CustomTokenRecord
                .filter(Safe4CustomTokenRecord.Columns.address.lowercased == address.lowercased())
                .filter(Safe4CustomTokenRecord.Columns.chainId == chainId)
                .fetchOne(db) else {
                return
            }
            record.logoURI = logo
            try record.update(db)
        }
   }

    func delete(by address: String) {
        delete(by: address, chainId: currentChainId)
    }

    func delete(by address: String, chainId: Int) {
        _ = try! dbPool.write { db in
            try Safe4CustomTokenRecord
                .filter(Safe4CustomTokenRecord.Columns.address.lowercased == address.lowercased())
                .filter(Safe4CustomTokenRecord.Columns.chainId == chainId)
                .deleteAll(db)
        }
    }

    func clear() throws {
        _ = try dbPool.write { db in
            try Safe4CustomTokenRecord.deleteAll(db)
        }
    }
}
