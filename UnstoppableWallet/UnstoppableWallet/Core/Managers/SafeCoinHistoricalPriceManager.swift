//  SafeCoinHistoricalPriceManager.swift
import Foundation
import SQLite
import MarketKit
import RxSwift
import GRDB

class SafeCoinHistoricalPriceManager {
    private let storage: CoinHistoricalPriceStorage
    private let hsProvider: SafeCoinPriceProvider

    init(storage: CoinHistoricalPriceStorage, hsProvider: SafeCoinPriceProvider) {
        self.storage = storage
        self.hsProvider = hsProvider
    }

}

extension SafeCoinHistoricalPriceManager {

    func coinHistoricalPriceValue(coinUid: String, currencyCode: String, timestamp: TimeInterval) -> Decimal? {
        try? storage.coinHistoricalPrice(coinUid: coinUid, currencyCode: currencyCode, timestamp: timestamp)?.value
    }

    func coinHistoricalPriceValueSingle(coinUid: String, currencyCode: String, timestamp: TimeInterval) -> Single<Decimal> {
        hsProvider.coinHistoricalPriceSingle(coinUid: coinUid, timestamp: timestamp)
                .flatMap { [weak self] response in
                    try? self?.storage.save(coinHistoricalPrice: CoinHistoricalPrice(coinUid: coinUid, currencyCode: currencyCode, value: Decimal(response.price), timestamp: timestamp))
                    return Single.just(Decimal(response.price))
                }
    }

}

extension SafeCoinHistoricalPriceManager {

    enum ResponseError: Error {
        case returnedTimestampIsTooInaccurate
    }

}

