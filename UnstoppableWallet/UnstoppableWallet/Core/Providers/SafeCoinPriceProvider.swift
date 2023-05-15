import Foundation
import RxSwift
import ObjectMapper
import HsToolKit
import Alamofire
import MarketKit
import GRDB

let safeCoinUid = "safe-anwang"
let safeCoinName = "SAFE"
let safeCoinCode = ""

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

    /// safe 历史价格获取
    func coinHistoricalPriceSingle(coinUid: String, timestamp: TimeInterval) -> Single<SafeCoinHistoricalPriceResponse> {
        let dateStr = formatTransactionDate(from: timestamp)
        
        let parameters: Parameters = [
            "date": dateStr
        ]
        return networkManager.single(url: "\(baseUrl)/coins/\(coinUid)/history", method: .get, parameters: parameters, headers: headers)
    }
}

extension SafeCoinPriceProvider {
    
    private func formatTransactionDate(from timestamp: TimeInterval) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd-MM-yyyy"
        let date = NSDate(timeIntervalSince1970: timestamp) as Date
        return dateFormatter.string(from: date)
    }
}

struct SafeCoinHistoricalPriceResponse: ImmutableMappable {
   // let timestamp: Int
    let price: Double

    init(map: Map) throws {
      //  timestamp = try map.value("timestamp")
        price = try map.value("market_data.current_price.\(App.shared.currencyKit.baseCurrency.code.lowercased())")
    }
}
