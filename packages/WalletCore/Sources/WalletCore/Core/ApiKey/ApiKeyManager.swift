import HsToolKit
import RxSwift

class ApiKeyManager {

    let service: ApiKeyService

    init(networkManager: NetworkManager) {
       let provider = ApiKeyProvider(networkManager: networkManager)
        service = ApiKeyService(provider: provider)
    }

    static func apiKeys(name: ApiKeyName) -> [String]? {
        ApiKeyService.getCacheApiKeys().filter{$0.name == name.rawValue}.first?.key
    }

    static func rpcEndpoint(network: RpcNetworkName) -> String? {
        rpcEndpointConfig(network: network)?.endpoint
    }

    static func rpcEndpointConfig(network: RpcNetworkName) -> RpcEndpoint? {
        ApiKeyService.getCacheRpcEndpoints().first { $0.network == network.rawValue }
    }

    static var rpcEndpointsUpdatedObservable: Observable<[RpcEndpointChange]> {
        ApiKeyService.rpcEndpointsUpdatedObservable
    }
}
