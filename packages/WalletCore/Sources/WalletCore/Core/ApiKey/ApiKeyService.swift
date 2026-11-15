import RxSwift
import Foundation
import RxRelay
import MarketKit

let RPC_ENDPOINT_KEY = "rpc_endpoint_key"
let API_KEY_KEY = "api_key_key"

class ApiKeyService {
    private static let rpcEndpointsUpdatedRelay = PublishRelay<Set<RpcNetworkName>>()

    private var disposeBag = DisposeBag()
    private let apiKeyProvider: ApiKeyProvider
    private let userDefaultsStorage: UserDefaultsStorage

    init(provider: ApiKeyProvider) {
        self.apiKeyProvider = provider
        self.userDefaultsStorage = UserDefaultsStorage()
        update()
    }
}
private extension ApiKeyService {
    func update() {
        apiKeyProvider.rpcEndpointSingle()
            .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .subscribe(onSuccess: { [weak self] datas in
                self?.cacheRpcEndpoint(datas)
            }, onError: { [weak self] error in
            })
            .disposed(by: disposeBag)

        apiKeyProvider.apiKeysSingle()
            .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .subscribe(onSuccess: { [weak self] datas in
                self?.cacheApiKeys(datas)
            }, onError: { [weak self] error in
            })
            .disposed(by: disposeBag)
    }

    func cacheRpcEndpoint(_ rpcEndpoints: [RpcEndpoint]) {
        let updatedNetworks = Self.updatedRpcNetworks(from: Self.getCacheRpcEndpoints(), to: rpcEndpoints)

        do {
            let encoder = JSONEncoder()
            let encodedData = try encoder.encode(rpcEndpoints)
            userDefaultsStorage.set(value: encodedData, for: RPC_ENDPOINT_KEY)
            if !updatedNetworks.isEmpty {
                Self.rpcEndpointsUpdatedRelay.accept(updatedNetworks)
            }

        } catch {
            print("encode Failed: \(error)")
        }
    }

    func cacheApiKeys(_ keys: [ApiKey]) {
        do {
            let encoder = JSONEncoder()
            let encodedData = try encoder.encode(keys)
            userDefaultsStorage.set(value: encodedData, for: API_KEY_KEY)
        } catch {
            print("encode Failed: \(error)")
        }

    }
}

extension ApiKeyService {
    static func updatedRpcNetworks(from previous: [RpcEndpoint], to updated: [RpcEndpoint]) -> Set<RpcNetworkName> {
        Set(RpcNetworkName.allCases.filter { network in
            previous.first { $0.network == network.rawValue }?.endpoint
                != updated.first { $0.network == network.rawValue }?.endpoint
        })
    }

    static var rpcEndpointsUpdatedObservable: Observable<Set<RpcNetworkName>> {
        rpcEndpointsUpdatedRelay.asObservable()
    }

    static func getCacheRpcEndpoints() -> [RpcEndpoint] {
        if let data: Data = UserDefaultsStorage().value(for: RPC_ENDPOINT_KEY) {
            do {
                let decoder = JSONDecoder()
                let decodedData = try decoder.decode([RpcEndpoint].self, from: data)
                return decodedData
            } catch {
                print("decode Failed: \(error)")
                return []
            }
        }
        return []
    }

    static func getCacheApiKeys() -> [ApiKey] {
        if let data: Data = UserDefaultsStorage().value(for: API_KEY_KEY) {
            do {
                let decoder = JSONDecoder()
                let decodedData = try decoder.decode([ApiKey].self, from: data)
                return decodedData
            } catch {
                print("decode Failed: \(error)")
                return []
            }
        }
        return []
    }
}
