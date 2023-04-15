import Foundation
import RxSwift
import ObjectMapper
import HsToolKit
import Alamofire
import MarketKit

let safeCoinUid = "safe-anwang"
let safeCoinName = "SAFE(AnWang)"
let safeCoinCode = "SAFE"

class SafeCoinPriceProvider {
    private let baseUrl: String = "https://api.coingecko.com/api/v3"
    private let networkManager: NetworkManager
    private let headers: HTTPHeaders?
    
    init(networkManager: NetworkManager, appConfigProvider: AppConfigProvider) {
        self.networkManager = networkManager
        headers = appConfigProvider.hsProviderApiKey.flatMap { HTTPHeaders([HTTPHeader(name: "apikey", value: $0)]) }
    }
}

extension SafeCoinPriceProvider {
    /// safe 最新价格获取
    func coinCurrentPriceSingle(coinUids: [String], currencyCode: String) -> Single<[SafeCoinPriceResponse]> {
        let idsStr = coinUids.joined(separator: ",")
        let parameters: Parameters = [
            "ids": idsStr,
            "vs_currency": currencyCode
        ]
        return networkManager.single(url: "\(baseUrl)/coins/markets", method: .get, parameters: parameters, headers: nil)
    }
    
//    /// safe 历史价格获取
//    func coinHistoricalPriceSingle(coinUid: String, timestamp: TimeInterval) -> Single<SafeCoinHistoricalPriceResponse> {
//        let dateStr = formatTransactionDate(from: timestamp)
//        
//        let parameters: Parameters = [
//            "date": dateStr
//        ]
//        return networkManager.single(url: "\(baseUrl)/coins/\(coinUid)/history", method: .get, parameters: parameters, headers: headers)
//    }
}

extension SafeCoinPriceProvider {
    
    private func formatTransactionDate(from timestamp: TimeInterval) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd-mm-yyyy"
        let date = NSDate(timeIntervalSince1970: timestamp) as Date
        return dateFormatter.string(from: date)
    }
    

}

struct SafeCoinPriceResponse: ImmutableMappable {

    let id: String
    let symbol: String
    let name: String
    let image: String
    let current_price: Double
    let market_cap: Double
    let market_cap_rank: String?
    let fully_diluted_valuation: String?
    let total_volume: Double
    let high_24h: Double
    let low_24h: Double
    let price_change_24h: Double
    let price_change_percentage_24h: Double
    let market_cap_change_24h: Double
    let market_cap_change_percentage_24h: Double
    let circulating_supply: Double
    let total_supply: String?
    let max_supply: String?
    let ath: Double
    let ath_change_percentage: Double
    let ath_date: String
    let atl: Double
    let atl_change_percentage: Double
    let atl_date: String
    let roi: String?
    let last_updated: String
    
    public var expired: Bool {
        Date().timeIntervalSince1970 - utcDateFormatter().date(from: last_updated)!.timeIntervalSince1970 > Self.expirationInterval
    }

    init(map: Map) throws {
        id = try map.value("id")
        symbol = try map.value("symbol")
        name = try map.value("name")
        image = try map.value("image")
        current_price = try map.value("current_price")
        market_cap = try map.value("market_cap")
        market_cap_rank = try? map.value("market_cap_rank")
        fully_diluted_valuation = try? map.value("fully_diluted_valuation")
        total_volume = try map.value("total_volume")
        high_24h = try map.value("high_24h")
        low_24h = try map.value("low_24h")
        price_change_24h = try map.value("price_change_24h")
        price_change_percentage_24h = try map.value("price_change_percentage_24h")
        market_cap_change_24h = try map.value("market_cap_change_24h")
        market_cap_change_percentage_24h = try map.value("market_cap_change_percentage_24h")
        circulating_supply = try map.value("circulating_supply")
        total_supply = try map.value("total_supply")
        max_supply = try map.value("max_supply")
        ath = try map.value("ath")
        ath_change_percentage = try map.value("ath_change_percentage")
        ath_date = try map.value("ath_date")
        atl = try map.value("atl")
        atl_change_percentage = try map.value("atl_change_percentage")
        atl_date = try map.value("atl_date")
        roi = try? map.value("roi")
        last_updated = try map.value("last_updated")
    }
}

extension SafeCoinPriceResponse {
    
    static let expirationInterval: TimeInterval = 240

    func utcDateFormatter() -> DateFormatter {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        dateFormatter.timeZone = TimeZone(abbreviation: "GMT")!
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        return dateFormatter
    }
}
