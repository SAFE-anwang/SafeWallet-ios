import Foundation
import GRDB
import MarketKit

class SafeCoinPriceStorage {

    private let dbPool: DatabasePool

    init(dbPool: DatabasePool) throws {
        self.dbPool = dbPool
        try migrator.migrate(dbPool)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("Create SafeCoinPrice") { db in
            try db.create(table: SafeCoinPrice.databaseTableName) { t in
                t.column(SafeCoinPrice.Columns.coinUid.name, .text).notNull()
                t.column(SafeCoinPrice.Columns.currencyCode.name, .text).notNull()
                t.column(SafeCoinPrice.Columns.value.name, .text)
                t.column(SafeCoinPrice.Columns.diff.name, .double)
                t.column(SafeCoinPrice.Columns.timestamp.name, .double)
                t.primaryKey([SafeCoinPrice.Columns.coinUid.name, SafeCoinPrice.Columns.currencyCode.name], onConflict: .replace)
            }
        }

        return migrator
    }
}

extension SafeCoinPriceStorage {

    func coinPrice(coinUid: String, currencyCode: String) throws -> SafeCoinPrice? {
        try dbPool.read { db in
            try SafeCoinPrice.filter(SafeCoinPrice.Columns.coinUid == coinUid && SafeCoinPrice.Columns.currencyCode == currencyCode).fetchOne(db)
        }
    }

    func coinPrices(coinUids: [String], currencyCode: String) throws -> [SafeCoinPrice] {
        try dbPool.read { db in
            try SafeCoinPrice.filter(coinUids.contains(SafeCoinPrice.Columns.coinUid) && SafeCoinPrice.Columns.currencyCode == currencyCode).fetchAll(db)
        }
    }

    func coinPricesSortedByTimestamp(coinUids: [String], currencyCode: String) throws -> [SafeCoinPrice] {
        try dbPool.read { db in
            try SafeCoinPrice
                .filter(coinUids.contains(SafeCoinPrice.Columns.coinUid) && SafeCoinPrice.Columns.currencyCode == currencyCode)
                .order(SafeCoinPrice.Columns.timestamp)
                    .fetchAll(db)
        }
    }

    func save(coinPrices: [SafeCoinPrice]) throws {
        _ = try dbPool.write { db in
            for coinPrice in coinPrices {
                try coinPrice.insert(db)
            }
        }
    }

}

class SafeCoinPrice: Record {
    static let expirationInterval: TimeInterval = 240

    public let coinUid: String
    public let currencyCode: String
    public let value: Decimal
    public let diff: Decimal
    public let timestamp: TimeInterval

    enum Columns: String, ColumnExpression, CaseIterable {
        case coinUid, currencyCode, value, diff, timestamp
    }

    init(coinUid: String, currencyCode: String, value: Decimal, diff: Decimal, timestamp: TimeInterval) {
        self.coinUid = coinUid
        self.currencyCode = currencyCode
        self.value = value
        self.diff = diff
        self.timestamp = timestamp

        super.init()
    }

    override open class var databaseTableName: String {
        "coinPrice"
    }

    required init(row: Row) throws {
        coinUid = row[Columns.coinUid]
        currencyCode = row[Columns.currencyCode]
        value = row[Columns.value]
        diff = row[Columns.diff]
        timestamp = row[Columns.timestamp]

        try super.init(row: row)
    }

    override open func encode(to container: inout PersistenceContainer) {
        container[Columns.coinUid] = coinUid
        container[Columns.currencyCode] = currencyCode
        container[Columns.value] = value
        container[Columns.diff] = diff
        container[Columns.timestamp] = timestamp
    }

    public var expired: Bool {
        Date().timeIntervalSince1970 - timestamp > Self.expirationInterval
    }

}

extension SafeCoinPrice: CustomStringConvertible {

    public var description: String {
        "CoinPrice [coinUid: \(coinUid); currencyCode: \(currencyCode); value: \(value); diff: \(diff); timestamp: \(timestamp)]"
    }

}
