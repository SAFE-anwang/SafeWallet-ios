import Alamofire
import Combine
import Foundation
import HsToolKit
import ObjectMapper
import RxSwift

class Safe4Provider {
    private let networkSession = Safe4NetworkSession()
    private let networkManager: NetworkManager
    private let chainId: Int
    private let headers: HTTPHeaders?

    init(networkManager: NetworkManager, chainId: Int = Safe4Network.currentChainId) {
        self.networkManager = networkManager
        self.chainId = chainId
        headers = AppConfig.hsProviderApiKey.flatMap { HTTPHeaders([HTTPHeader(name: "apikey", value: $0)]) }
    }
}

extension Safe4Provider {
    func getRewardsSingle(address: String) -> Single<[Safe4Reward]> {
        do {
            try networkSession.check()
            let context = try Safe4Network.activeContext(chainId: chainId)
            let request = networkManager.session.request("\(context.apiBaseUrl)/api/rewards/\(address)", headers: headers)
            return networkManager.safe4Single(request: request).map { [networkSession] value in
                try networkSession.check()
                return value
            }
        } catch { return .error(error) }
    }
}

extension Safe4Provider {
    func marketkLinesSingle(token0: String, token1: String, interval: String) -> Single<[SafeKLineItem]> {
        let parameters: Parameters = [
            "token0": token0,
            "token1": token1,
            "interval": interval,
        ]
        do {
            try networkSession.check()
            let context = try Safe4Network.activeContext(chainId: chainId)
            let request = networkManager.session.request("\(context.apiBaseUrl)/list/market/klines", parameters: parameters, headers: [])
            return networkManager.single(request: request).map { [networkSession] value in
                try networkSession.check()
                return value
            }
        } catch { return .error(error) }
    }

    func wsafePricesSingle() -> Single<[KLineWSafeTokenPriceModel]>{
        do {
            try networkSession.check()
            let context = try Safe4Network.activeContext(chainId: chainId)
            let request = networkManager.session.request("\(context.apiBaseUrl)/list/market/prices", parameters: [:], headers: [])
            return networkManager.single(request: request).map { [networkSession] value in
                try networkSession.check()
                return value
            }
        } catch { return .error(error) }
    }

}

public extension NetworkManager {
    func safe4Single<T: ImmutableMappable>(request: DataRequest, context: MapContext? = nil) -> Single<[T]> {
        Single<[T]>.create { [weak self] observer in
            guard let manager = self else {
                observer(.error(NetworkManager.RequestError.disposed))
                return Disposables.create()
            }

            let task = Task {
                do {
                    guard let json = try await manager.fetchJson(request: request) as? NSDictionary, let jsonData = json["result"]  else { return observer(.error("Json Error" as! Error))}
                    let result = try Mapper<T>(context: context).mapArray(JSONObject: jsonData)
                    observer(.success(result))
                } catch {
                    observer(.error(error))
                }
            }

            return Disposables.create {
                task.cancel()
                request.cancel()
            }
        }
    }
}
