import Foundation
import RxSwift
import ObjectMapper
import HsToolKit
import Alamofire
import MarketKit
import GRDB

let safeCoinUid = "safe-anwang"
let safeCoinName = "SAFE"
let safeCoinCode = "SAFE"

class SafeCoinPriceProvider {
    private let baseUrl: String = "https://api.coingecko.com/api/v3"
    private let networkManager: NetworkManager
    private let headers: HTTPHeaders?
    
    init(networkManager: NetworkManager) {
        self.networkManager = networkManager
        headers = AppConfig.hsProviderApiKey.flatMap { HTTPHeaders([HTTPHeader(name: "apikey", value: $0)]) }
    }
}

extension SafeCoinPriceProvider {

    /// safe 历史价格获取
    func coinHistoricalPrice(coinUid: String, timestamp: TimeInterval) async throws -> SafeCoinHistoricalPriceResponse? {
        let dateStr = formatTransactionDate(from: timestamp)
        
        let parameters: Parameters = [
            "date": dateStr
        ]
        let usersResponse: SafeCoinHistoricalPriceResponse = try await networkManager.fetch(url: "\(baseUrl)/coins/\(coinUid)/history", method: .get, parameters: parameters, headers: headers)
        return usersResponse
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
        price = try map.value("market_data.current_price.\(App.shared.currencyManager.baseCurrency.code.lowercased())")
    }
}
