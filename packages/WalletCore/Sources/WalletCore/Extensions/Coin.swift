import Combine
import MarketKit
import UIKit

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

extension Coin {
    var imageUrl: String {
        let scale = Int(UIScreen.main.scale)
        if uid.contains("custom-safe4-anwang") || uid.contains("custom-safe-anwang") || uid.isSafeCoin {
            if let logoUrl = SRC20SyncManager.logo(coinUid: uid.lowercased()) {
                return logoUrl.count > 0 ? logoUrl : "https://anwang.com/img/logos/safe.png"
            }
            return "https://anwang.com/img/logos/safe.png"
        }else {
            return "https://cdn.blocksdecoded.com/coin-icons/32px/\(uid)@\(scale)x.png"
        }
    }

    public static func imageUrl(uid: String) -> String {
        let scale = Int(UIScreen.main.scale)
        if uid.contains("custom-safe4-anwang") || uid.contains("custom-safe-anwang") || uid.isSafeCoin {
            if let logoUrl = SRC20SyncManager.logo(coinUid: uid.lowercased()) {
                return logoUrl.count > 0 ? logoUrl : "https://anwang.com/img/logos/safe.png"
            }
            return "https://anwang.com/img/logos/safe.png"
        }else {
            return "https://cdn.blocksdecoded.com/coin-icons/32px/\(uid)@\(scale)x.png"
        }
    }

    // Same rule as the server: a coin re-listed on another chain keeps the original coingecko_id
    var isSynthetic: Bool {
        guard let coinGeckoId else { return false }
        return coinGeckoId != uid
    }
}
