import Combine
import MarketKit

private extension String {
    var walletPriceLookupUid: String {
        isSafe4Src20Token ? lowercased() : self
    }
}

public extension MarketKit.Kit {
    /// Reads prices using the UID normalization used by MarketKit 3.6.31 for Safe4 SRC20.
    /// All other assets retain their original UID and price source.
    func walletCoinPrice(coinUid: String, currencyCode: String) -> CoinPrice? {
        let lookupUid = coinUid.walletPriceLookupUid
        return coinPrice(coinUid: lookupUid, currencyCode: currencyCode)
            ?? (lookupUid == coinUid ? nil : coinPrice(coinUid: coinUid, currencyCode: currencyCode))
    }

    func walletCoinPriceMap(coinUids: [String], currencyCode: String) -> [String: CoinPrice] {
        let lookupUids = Array(Set(coinUids.map(\.walletPriceLookupUid)))
        let marketPrices = coinPriceMap(coinUids: lookupUids, currencyCode: currencyCode)

        var result = [String: CoinPrice]()
        for coinUid in coinUids {
            if let price = marketPrices[coinUid.walletPriceLookupUid] ?? marketPrices[coinUid] {
                result[coinUid] = price
            }
        }

        return result
    }

    func walletCoinPricePublisher(coinUid: String, currencyCode: String) -> AnyPublisher<CoinPrice, Never> {
        coinPricePublisher(coinUid: coinUid.walletPriceLookupUid, currencyCode: currencyCode)
    }

    func walletCoinPriceMapPublisher(coinUids: [String], currencyCode: String) -> AnyPublisher<[String: CoinPrice], Never> {
        let lookupUids = Array(Set(coinUids.map(\.walletPriceLookupUid)))

        return coinPriceMapPublisher(coinUids: lookupUids, currencyCode: currencyCode)
            .map { marketPrices in
                var result = [String: CoinPrice]()
                for coinUid in coinUids {
                    if let price = marketPrices[coinUid.walletPriceLookupUid] ?? marketPrices[coinUid] {
                        result[coinUid] = price
                    }
                }
                return result
            }
            .eraseToAnyPublisher()
    }
}
