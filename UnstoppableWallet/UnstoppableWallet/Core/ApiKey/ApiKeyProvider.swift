import Foundation
import RxSwift
import HsToolKit
import ObjectMapper
import Alamofire


class ApiKeyProvider {
    
    private let baseUrl = "https://safewallet.anwang.com"
    private let networkManager: NetworkManager

    init(networkManager: NetworkManager) {
        self.networkManager = networkManager
    }

    func rpcEndpointSingle() -> Single<[RpcEndpoint]> {
         let ur = URL(string: "\(baseUrl)/v1/evm/rpc/services")!
        let request = networkManager.session.request(ur)
        return networkManager.single(request: request)
    }
    
    func apiKeysSingle() -> Single<[ApiKey]> {
        let ur = URL(string: "\(baseUrl)/v1/apiKeys")!

        let request = networkManager.session.request(ur)
        return networkManager.single(request: request)
    }
}

struct RpcEndpoint: ImmutableMappable, Codable {
    
    let id: String
    let endpoint: String
    let network: String
    let networkId: String
    let type: String

    init(map: Map) throws {
        id = try map.value("id", default: "")
        endpoint = try map.value("endpoint", default: "")
        network = try map.value("network", default: "")
        networkId = try map.value("networkId", default: "")
        type = try map.value("type", default: "")
    }
}

struct ApiKey: ImmutableMappable, Codable {
    let name: String?
    let key: [String]
    
    init(map: Map) throws {
        name = try? map.value("name")
        key = (try? map.value("key")) ?? []
    }
}

enum ApiKeyName: String {
    case walletConnectV2, solscan, polygonscan, arbiscan, etherscan, bscscan, twitterBearerToken, infura, gnosisscan, oneInch, optimisticEtherscan, ftmscan
}

enum RpcNetworkName: String {
    case eth, bsc, p2pify, polygon, optimism, arbitrum, avax, gnosis, fantom, safe4, sol
    case safe4_testnet = "safe4-testnet"
}
