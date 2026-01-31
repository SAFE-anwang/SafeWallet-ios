
import Foundation
import RxSwift
import ObjectMapper
import HsToolKit
import Alamofire
import MarketKit
import GRDB

class SafeProvider {
    private let baseUrl: String = "https://safewallet.anwang.com"
    private let networkManager: NetworkManager
    private let headers: HTTPHeaders?
    
    init(networkManager: NetworkManager) {
        self.networkManager = networkManager
        headers = AppConfig.hsProviderApiKey.flatMap { HTTPHeaders([HTTPHeader(name: "apikey", value: $0)]) }
    }
}

extension SafeProvider {
    func getCrossChainConfigForSafe4Native() -> Single<CrossChainSafe4NativeConfig> {
        let netType = AppConfig.isSafe4TestNet ? "testnet4" : "mainnet4"
        return networkManager.single(url: "\(baseUrl)/v1/gate/\(netType)", method: .get, parameters: [:], headers: nil)
    }
    
    func getCrossChainConfigForSafe4USDT() -> Single<CrossChainSafe4USDTConfig> {
        let netType = AppConfig.isSafe4TestNet ? "testnet4" : "mainnet4"
        return networkManager.single(url: "\(baseUrl)/v1/gate/\(netType)/usdt", method: .get, parameters: [:], headers: nil)
    }
}
