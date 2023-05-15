import Foundation
import RxSwift
import HsToolKit
import Alamofire
import ObjectMapper

class CoinGeckoProvider {
    private let baseUrl = "https://api.coingecko.com/api/v3"
    
    private let safeBaseUrl: String = "https://safewallet.anwang.com/api/v3"
    private let safeCoinUid: String = "safe-anwang"
    
    private let networkManager: NetworkManager

    init(networkManager: NetworkManager) {
        self.networkManager = networkManager
    }

}

extension CoinGeckoProvider {

    func exchangesSingle(limit: Int, page: Int) -> Single<[Exchange]> {
        let parameters: Parameters = [
            "per_page": limit,
            "page": page
        ]

        return networkManager.single(url: "\(baseUrl)/exchanges", method: .get, parameters: parameters)
    }

    func marketTickersSingle(coinId: String) -> Single<CoinGeckoCoinResponse> {
        let parameters: Parameters = [
            "tickers": "true",
            "localization": "false",
            "market_data": "false",
            "community_data": "false",
            "developer_data": "false",
            "sparkline": "false"
        ]

        return networkManager.single(url: "\(baseUrl)/coins/\(coinId)", method: .get, parameters: parameters)
    }

}

// safe Coin
extension CoinGeckoProvider {
    
    func safeMarketTickersSingle(coinId: String) -> Single<CoinGeckoCoinResponse> {
        let parameters: Parameters = [
            "tickers": "true",
            "localization": "false",
            "market_data": "false",
            "community_data": "false",
            "developer_data": "false",
            "sparkline": "false"
        ]
        return networkManager.single(url: "\(safeBaseUrl)/coins/\(coinId)", method: .get, parameters: parameters)
    }
}
