
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
    func getSafeInfo(netType: String) -> Single<SafeChainInfo> {
        let parameters: Parameters = [:]
        return networkManager.single(url: "\(baseUrl)/v1/gate/\(netType)", method: .get, parameters: parameters, headers: nil)
    }
}
