import HsToolKit

class ApiKeyManager {
    
    let service: ApiKeyService
    
    init(networkManager: NetworkManager) {
       let provider = ApiKeyProvider(networkManager: networkManager)
        service = ApiKeyService(provider: provider)
    }
    
    static func getApiKey(name: ApiKeyName) -> [String]? {
        ApiKeyService.getCacheApiKeys().filter{$0.name == name.rawValue}.first?.key
    }
    
    static func rpcEndpoint(network: RpcNetworkName) -> String? {
        ApiKeyService.getCacheRpcEndpoints().filter{$0.network == network.rawValue}.first?.endpoint
    }
}

