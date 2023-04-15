import Foundation
import GRDB

class CoinHistoricalPriceStorage {
    private let dbPool: DatabasePool

    init(dbPool: DatabasePool) {
        self.dbPool = dbPool
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

    required init(row: Row) {
        coinUid = row[Columns.coinUid]
        currencyCode = row[Columns.currencyCode]
        value = row[Columns.value]
        timestamp = row[Columns.timestamp]

        super.init(row: row)
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
