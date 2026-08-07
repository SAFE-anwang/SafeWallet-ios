import GRDB

class OpenCryptoPayPaymentStorage {
    private let dbPool: DatabasePool

    init(dbPool: DatabasePool) {
        self.dbPool = dbPool
    }

    private typealias R = OpenCryptoPayPaymentRecord
}

extension OpenCryptoPayPaymentStorage {
    func record(transactionHash: String, accountId: String) throws -> OpenCryptoPayPaymentRecord? {
        try dbPool.read { db in
            try R.filter(R.Columns.accountId == accountId && R.Columns.transactionHash == transactionHash).fetchOne(db)
        }
    }

    func pending() throws -> [OpenCryptoPayPaymentRecord] {
        try dbPool.read { db in
            try R.filter(R.Columns.proofSubmittedAt == nil && R.Columns.proofFailedAt == nil).fetchAll(db)
        }
    }

    func insert(record: OpenCryptoPayPaymentRecord) throws {
        try dbPool.write { db in try record.insert(db) }
    }

    func markSubmitted(transactionHash: String, accountId: String, at: Double) throws {
        _ = try dbPool.write { db in
            try R.filter(R.Columns.accountId == accountId && R.Columns.transactionHash == transactionHash)
                .updateAll(db, R.Columns.proofSubmittedAt.set(to: at), R.Columns.proofFailedAt.set(to: nil))
        }
    }

    func markFailed(transactionHash: String, accountId: String, at: Double) throws {
        _ = try dbPool.write { db in
            try R.filter(R.Columns.accountId == accountId && R.Columns.transactionHash == transactionHash)
                .updateAll(db, R.Columns.proofFailedAt.set(to: at))
        }
    }

    func markAttempted(transactionHash: String, accountId: String, at: Double) throws {
        _ = try dbPool.write { db in
            try R.filter(R.Columns.accountId == accountId && R.Columns.transactionHash == transactionHash)
                .updateAll(db, R.Columns.lastAttemptedAt.set(to: at))
        }
    }

    func clear(accountId: String) throws {
        _ = try dbPool.write { db in
            try R.filter(R.Columns.accountId == accountId).deleteAll(db)
        }
    }

    func clear(parentAccountId: String) throws {
        _ = try dbPool.write { db in
            try db.execute(
                sql: """
                DELETE FROM \(R.databaseTableName)
                WHERE \(R.Columns.accountId.name) = ?
                    OR \(R.Columns.accountId.name) LIKE ?
                """,
                arguments: [parentAccountId, "\(parentAccountId):child:%"]
            )
        }
    }

    func clear(exceptParentAccountIds accountIds: [String]) throws {
        _ = try dbPool.write { db in
            guard !accountIds.isEmpty else {
                try R.deleteAll(db)
                return
            }

            let rootPlaceholders = Array(repeating: "?", count: accountIds.count).joined(separator: ", ")
            let childPredicates = accountIds.map { _ in "\(R.Columns.accountId.name) LIKE ?" }.joined(separator: " OR ")
            let arguments = StatementArguments(accountIds + accountIds.map { "\($0):child:%" })

            try db.execute(
                sql: """
                DELETE FROM \(R.databaseTableName)
                WHERE \(R.Columns.accountId.name) NOT IN (\(rootPlaceholders))
                    AND NOT (\(childPredicates))
                """,
                arguments: arguments
            )
        }
    }
}
