import Foundation
import SQLite
import MarketKit
import RxSwift
import GRDB

extension SafeCoinPriceManager {
    
    enum ResponseError: Error {
        case returnedTimestampIsTooInaccurate
    }
}

class SafeCoinPriceManager {

    private let storage: SafeCoinPriceStorage
    private let hsProvider: SafeCoinPriceProvider
    
    var safeIconUrlStr: String?
    
    private static var utcDateFormatter: DateFormatter {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        dateFormatter.timeZone = TimeZone(abbreviation: "GMT")!
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        return dateFormatter
    }

    init(storage: SafeCoinPriceStorage, hsProvider: SafeCoinPriceProvider) {
        self.storage = storage
        self.hsProvider = hsProvider
    }

    private func notify(coinPrices: [SafeCoinPrice], currencyCode: String) {
        var coinPriceMap = [String: SafeCoinPrice]()

        coinPrices.forEach { coinPrice in
            coinPriceMap[coinPrice.coinUid] = coinPrice
        }
    }

}

extension SafeCoinPriceManager {
    
    func coinPriceValue(coinUid: String, currencyCode: String) -> Decimal? {
        try? storage.coinPrice(coinUid: coinUid, currencyCode: currencyCode)?.value
    }

    func coinPriceValueSingle(coinUids: [String], currencyCode: String) -> Single<[String: SafeCoinPrice]> {
        hsProvider.coinCurrentPriceSingle(coinUids: coinUids, currencyCode: currencyCode)
                .flatMap { [weak self] responses in
                    var map = [String: SafeCoinPrice]()
                    let coinPrices = responses.map { response in
                        if response.name == safeCoinName {
                            self?.safeIconUrlStr = response.image
                        }

                        let timestamp = SafeCoinPriceManager.utcDateFormatter.date(from: response.last_updated)!.timeIntervalSince1970
                         let safeCoinPrice = SafeCoinPrice(coinUid:  response.id, currencyCode: currencyCode, value: Decimal(response.current_price), diff: Decimal(response.price_change_percentage_24h), timestamp: timestamp)
                        map[response.id] = safeCoinPrice
                        return safeCoinPrice
                    }
                    try? self?.storage.save(coinPrices: coinPrices)
                    return Single.just(map)
                }
    }
}

extension SafeCoinPriceManager {

    func lastSyncTimestamp(coinUids: [String], currencyCode: String) -> TimeInterval? {
        do {
            let coinPrices = try storage.coinPricesSortedByTimestamp(coinUids: coinUids, currencyCode: currencyCode)

            // not all records for coin codes are stored in database - force sync required
            guard coinPrices.count == coinUids.count else {
                return nil
            }

            // return date of the most expired stored record
            return coinPrices.first?.timestamp
        } catch {
            return nil
        }
    }

    func coinPrice(coinUid: String, currencyCode: String) -> SafeCoinPrice? {
        try? storage.coinPrice(coinUid: coinUid, currencyCode: currencyCode)
    }

    func coinPriceMap(coinUids: [String], currencyCode: String) -> [String: SafeCoinPrice] {
        var map = [String: SafeCoinPrice]()
        do {
            for coinPrice in try storage.coinPrices(coinUids: coinUids, currencyCode: currencyCode) {
                map[coinPrice.coinUid] = coinPrice
            }
        } catch {
        }
        return map
    }

    func handleUpdated(coinPrices: [SafeCoinPrice], currencyCode: String) {
        do {
            try storage.save(coinPrices: coinPrices)
            notify(coinPrices: coinPrices, currencyCode: currencyCode)
        } catch {
            // todo
        }
    }

    func notifyExpired(coinUids: [String], currencyCode: String) {
        do {
            let coinPrices = try storage.coinPrices(coinUids: coinUids, currencyCode: currencyCode)
            notify(coinPrices: coinPrices, currencyCode: currencyCode)
        } catch {
            // todo
        }
    }

}

