import Foundation
import SQLite
import MarketKit
import GRDB
import HsExtensions

class SafeCoinHistoricalPriceManager {
    private let storage: CoinHistoricalPriceStorage
    private let hsProvider: SafeCoinPriceProvider
    private var tasks = Set<AnyTask>()


    init(storage: CoinHistoricalPriceStorage, hsProvider: SafeCoinPriceProvider) {
        self.storage = storage
        self.hsProvider = hsProvider
    }

}

extension SafeCoinHistoricalPriceManager {

    func coinHistoricalPriceValue(coinUid: String, currencyCode: String, timestamp: TimeInterval) async throws -> Decimal? {
        if let price = try? storage.coinHistoricalPrice(coinUid: coinUid, currencyCode: currencyCode, timestamp: timestamp)?.value {
            return price
        }else {
            guard let price = try await hsProvider.coinHistoricalPrice(coinUid: coinUid, timestamp: timestamp)?.price else { return nil }
            try? storage.save(coinHistoricalPrice: CoinHistoricalPrice(coinUid: coinUid, currencyCode: currencyCode, value: Decimal(price), timestamp: timestamp))
            return Decimal(price)
        }
    }
}

extension SafeCoinHistoricalPriceManager {

    enum ResponseError: Error {
        case returnedTimestampIsTooInaccurate
    }

}

