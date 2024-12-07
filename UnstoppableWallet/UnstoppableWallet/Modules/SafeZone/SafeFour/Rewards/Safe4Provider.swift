import Alamofire
import Combine
import Foundation
import HsToolKit
import ObjectMapper
import RxSwift

class Safe4Provider {
    private let networkManager: NetworkManager
    private let apiUrl = "https://safe4.anwang.com/api/"
    private let headers: HTTPHeaders?

    init(networkManager: NetworkManager) {
        self.networkManager = networkManager
        headers = AppConfig.hsProviderApiKey.flatMap { HTTPHeaders([HTTPHeader(name: "apikey", value: $0)]) }
    }
}

extension Safe4Provider {
    func getRewardsSingle(address: String) -> Single<[Safe4Reward]> {
        let request = networkManager.session.request("\(apiUrl)/rewards/\(address)", headers: headers)
        return networkManager.safe4Single(request: request)
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
            }
        }
    }
}
