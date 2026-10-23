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
        migrator.registerMigration("safe4 custom token promotion state") { db in
            let tableName = Safe4CustomTokenRecord.databaseTableName
            try db.alter(table: tableName) { t in
                t.add(column: Safe4CustomTokenRecord.Columns.isPromoted.name, .boolean).notNull().defaults(to: false)
            }
            try db.execute(sql: """
                UPDATE \(tableName)
                SET isPromoted = CASE WHEN logoURI IS NOT NULL AND TRIM(logoURI) <> '' THEN 1 ELSE 0 END
                """)
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

    func synchronize(tokens: [Safe4CustomTokenRecord], ownedBy ownerAddress: String, ownedAddresses: Set<String>, chainId: Int) throws {
        let normalizedOwnerAddress = ownerAddress.lowercased()
        let normalizedOwnedAddresses = Set(ownedAddresses.map { $0.lowercased() })

        try dbPool.write { db in
            let existingRecords = try Safe4CustomTokenRecord
                .filter(Safe4CustomTokenRecord.Columns.chainId == chainId)
                .fetchAll(db)
            let existingByAddress = Dictionary(grouping: existingRecords) { $0.address.lowercased() }

            try db.execute(
                sql: "UPDATE \(Safe4CustomTokenRecord.databaseTableName) SET isPromoted = 0 WHERE chainId = ?",
                arguments: [chainId]
            )

            for record in existingRecords
            where record.creator.lowercased() == normalizedOwnerAddress
                && !normalizedOwnedAddresses.contains(record.address.lowercased()) {
                try record.delete(db)
            }

            for token in tokens {
                let addressRecords = existingByAddress[token.address.lowercased()] ?? []
                for existing in addressRecords where existing.address != token.address {
                    // EVM addresses are case-insensitive, while the table's primary key is not.
                    try existing.delete(db)
                }

                if token.version?.isEmpty != false,
                   let existingVersion = addressRecords.compactMap(\.version).first(where: { !$0.isEmpty }),
                   !existingVersion.isEmpty {
                    token.version = existingVersion
                }

                if token.logoURI == nil {
                    token.logoURI = addressRecords.compactMap(\.logoURI).first
                }

                if token.type == nil {
                    token.type = addressRecords.compactMap(\.type).first
                }

                try token.save(db)
            }
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

    func update(tokens: [Safe4CustomTokenRecord]) throws {
        guard !tokens.isEmpty else { return }

        try dbPool.write { db in
            for token in tokens {
                try token.update(db)
            }
        }
    }

    func updateVersions(_ versions: [String: String], chainId: Int) throws {
        guard !versions.isEmpty else { return }

        try dbPool.write { db in
            for (address, version) in versions {
                try db.execute(
                    sql: "UPDATE \(Safe4CustomTokenRecord.databaseTableName) SET version = ? WHERE lower(address) = lower(?) AND chainId = ?",
                    arguments: [version, address, chainId]
                )
            }
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
