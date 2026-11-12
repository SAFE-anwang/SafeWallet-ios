
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
    func getCrossChainConfigForSafe4Native(chainId: Int) -> Single<CrossChainSafe4NativeConfig> {
        guard let context = Safe4Network.context(chainId: chainId) else {
            return .error(Safe4NetworkError.unsupportedChain(chainId))
        }
        let netType = context.isTestNet ? "testnet4" : "mainnet4"
        return networkManager.single(url: "\(baseUrl)/v1/gate/\(netType)", method: .get, parameters: [:], headers: nil)
    }

    func getCrossChainConfigForSafe4USDT(chainId: Int) -> Single<CrossChainSafe4USDTConfig> {
        guard let context = Safe4Network.context(chainId: chainId) else {
            return .error(Safe4NetworkError.unsupportedChain(chainId))
        }
        let netType = context.isTestNet ? "testnet4" : "mainnet4"
        return networkManager.single(url: "\(baseUrl)/v1/gate/\(netType)/usdt", method: .get, parameters: [:], headers: nil)
    }
}
