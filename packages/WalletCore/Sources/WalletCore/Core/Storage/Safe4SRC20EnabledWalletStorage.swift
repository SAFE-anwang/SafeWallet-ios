import GRDB

class Safe4SRC20EnabledWalletStorage {
    private let dbPool: DatabasePool

    init(dbPool: DatabasePool) throws {
        self.dbPool = dbPool
        try migrator.migrate(dbPool)
    }

    var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("create safe4 src20 enabled wallets") { db in
            try db.create(table: Safe4SRC20EnabledWalletRecord.databaseTableName) { t in
                t.column(Safe4SRC20EnabledWalletRecord.Columns.accountId.name, .text).notNull()
                t.column(Safe4SRC20EnabledWalletRecord.Columns.chainId.name, .integer).notNull()
                t.column(Safe4SRC20EnabledWalletRecord.Columns.tokenQueryId.name, .text).notNull()
                t.column(Safe4SRC20EnabledWalletRecord.Columns.coinName.name, .text)
                t.column(Safe4SRC20EnabledWalletRecord.Columns.coinCode.name, .text)
                t.column(Safe4SRC20EnabledWalletRecord.Columns.coinImage.name, .text)
                t.column(Safe4SRC20EnabledWalletRecord.Columns.tokenDecimals.name, .integer)

                t.primaryKey([
                    Safe4SRC20EnabledWalletRecord.Columns.accountId.name,
                    Safe4SRC20EnabledWalletRecord.Columns.chainId.name,
                    Safe4SRC20EnabledWalletRecord.Columns.tokenQueryId.name
                ], onConflict: .replace)
            }
        }

        return migrator
    }
}

extension Safe4SRC20EnabledWalletStorage {
    func enabledWallets(chainId: Int) -> [EnabledWallet] {
        (try? dbPool.read { db in
            try Safe4SRC20EnabledWalletRecord
                .filter(Safe4SRC20EnabledWalletRecord.Columns.chainId == chainId)
                .fetchAll(db)
        }.map(\.enabledWallet)) ?? []
    }

    func enabledWallets(accountId: String, chainId: Int) -> [EnabledWallet] {
        (try? dbPool.read { db in
            try Safe4SRC20EnabledWalletRecord
                .filter(Safe4SRC20EnabledWalletRecord.Columns.accountId == accountId)
                .filter(Safe4SRC20EnabledWalletRecord.Columns.chainId == chainId)
                .fetchAll(db)
        }.map(\.enabledWallet)) ?? []
    }

    func handle(newEnabledWallets: [EnabledWallet], deletedEnabledWallets: [EnabledWallet], chainId: Int) {
        _ = try? dbPool.write { db in
            for enabledWallet in newEnabledWallets {
                _ = try Safe4SRC20EnabledWalletRecord
                    .filter(Safe4SRC20EnabledWalletRecord.Columns.accountId == enabledWallet.accountId)
                    .filter(Safe4SRC20EnabledWalletRecord.Columns.chainId == chainId)
                    .filter(Safe4SRC20EnabledWalletRecord.Columns.tokenQueryId.lowercased == enabledWallet.tokenQueryId.lowercased())
                    .deleteAll(db)
                try Safe4SRC20EnabledWalletRecord(enabledWallet: enabledWallet, chainId: chainId).insert(db)
            }

            for enabledWallet in deletedEnabledWallets {
                try Safe4SRC20EnabledWalletRecord
                    .filter(Safe4SRC20EnabledWalletRecord.Columns.accountId == enabledWallet.accountId)
                    .filter(Safe4SRC20EnabledWalletRecord.Columns.chainId == chainId)
                    .filter(Safe4SRC20EnabledWalletRecord.Columns.tokenQueryId.lowercased == enabledWallet.tokenQueryId.lowercased())
                    .deleteAll(db)
            }
        }
    }

    func replace(accountId: String, chainId: Int, enabledWallets: [EnabledWallet]) {
        _ = try? dbPool.write { db in
            try Safe4SRC20EnabledWalletRecord
                .filter(Safe4SRC20EnabledWalletRecord.Columns.accountId == accountId)
                .filter(Safe4SRC20EnabledWalletRecord.Columns.chainId == chainId)
                .deleteAll(db)

            for enabledWallet in enabledWallets {
                try Safe4SRC20EnabledWalletRecord(enabledWallet: enabledWallet, chainId: chainId).insert(db)
            }
        }
    }

    func delete(accountId: String) {
        _ = try? dbPool.write { db in
            try Safe4SRC20EnabledWalletRecord
                .filter(Safe4SRC20EnabledWalletRecord.Columns.accountId == accountId)
                .deleteAll(db)
        }
    }
}
