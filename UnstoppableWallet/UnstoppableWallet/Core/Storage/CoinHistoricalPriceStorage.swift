import Foundation
import GRDB

class CoinHistoricalPriceStorage {
    private let dbPool: DatabasePool

    init(dbPool: DatabasePool) throws {
        self.dbPool = dbPool
        try migrator.migrate(dbPool)
    }
    
    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("Create SafeCoinHistoricalPrice") { db in
            try db.create(table: CoinHistoricalPrice.databaseTableName) { t in
                t.column(CoinHistoricalPrice.Columns.coinUid.name, .text).notNull()
                t.column(CoinHistoricalPrice.Columns.currencyCode.name, .text).notNull()
                t.column(CoinHistoricalPrice.Columns.value.name, .text)
                t.column(CoinHistoricalPrice.Columns.timestamp.name, .double)
                t.primaryKey([CoinHistoricalPrice.Columns.coinUid.name, CoinHistoricalPrice.Columns.currencyCode.name], onConflict: .replace)
            }
        }

        return migrator
    }
}

extension CoinHistoricalPriceStorage {

    func coinHistoricalPrice(coinUid: String, currencyCode: String, timestamp: TimeInterval) throws -> CoinHistoricalPrice? {
        try dbPool.read { db in
            try CoinHistoricalPrice
                    .filter(CoinHistoricalPrice.Columns.coinUid == coinUid && CoinHistoricalPrice.Columns.currencyCode == currencyCode && CoinHistoricalPrice.Columns.timestamp == timestamp)
                    .fetchOne(db)
        }
    }

    func save(coinHistoricalPrice: CoinHistoricalPrice) throws {
        _ = try dbPool.write { db in
            try coinHistoricalPrice.insert(db)
        }
    }
}

class CoinHistoricalPrice: Record {

    public let coinUid: String
    public let currencyCode: String
    public let value: Decimal
    public let timestamp: TimeInterval

    enum Columns: String, ColumnExpression, CaseIterable {
        case coinUid, currencyCode, value, timestamp
    }

    init(coinUid: String, currencyCode: String, value: Decimal, timestamp: TimeInterval) {
        self.coinUid = coinUid
        self.currencyCode = currencyCode
        self.value = value
        self.timestamp = timestamp

        super.init()
    }

    override open class var databaseTableName: String {
        "coinHistoricalPrice"
    }

    required init(row: Row) throws {
        coinUid = row[Columns.coinUid]
        currencyCode = row[Columns.currencyCode]
        value = row[Columns.value]
        timestamp = row[Columns.timestamp]

        try super.init(row: row)
    }

    override open func encode(to container: inout PersistenceContainer) {
        container[Columns.coinUid] = coinUid
        container[Columns.currencyCode] = currencyCode
        container[Columns.value] = value
        container[Columns.timestamp] = timestamp
    }

}

extension CoinHistoricalPrice: CustomStringConvertible {

    public var description: String {
        "CoinHistoricalPrice [coinUid: \(coinUid); currencyCode: \(currencyCode); value: \(value); timestamp: \(timestamp)]"
    }

}
