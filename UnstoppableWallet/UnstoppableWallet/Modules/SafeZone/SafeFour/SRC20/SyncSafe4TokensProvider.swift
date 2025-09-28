import Foundation
import RxSwift
import HsToolKit
import ObjectMapper
import GRDB

class SyncSafe4TokensProvider {
    
    private let baseUrl = AppConfig.isSafe4TestNet == true ? "https://safe4testnet.anwang.com" : "https://safe4.anwang.com"
    private let networkManager: NetworkManager

    init(networkManager: NetworkManager) {
        self.networkManager = networkManager
    }
        
    func requestTokens() async throws -> Safe4TokensResponse {
         let urlString = "\(baseUrl)/list/token"
        let json = try await networkManager.fetchJson(url: urlString, method: .get, parameters: [:], responseCacherBehavior: .doNotCache)
        let result = try Safe4TokensResponse(JSONObject: json, context: nil)
        return result
    }
}
struct Safe4TokensResponse: ImmutableMappable, Decodable {
    let keywords: [String]
    let name: String
    let logoURI: String
    let version: Safe4CustomTokenVersion
    let timestamp: String
    let tokens: [Safe4CustomTokenRecord]

    init(map: Map) throws {
        keywords = (try? map.value("keywords")) ?? []
        name = try map.value("name")
        logoURI = try map.value("logoURI")
        tokens = try map.value("tokens")
        timestamp = try map.value("timestamp")
        version = try map.value("version")
    }
}

struct Safe4CustomTokenVersion: ImmutableMappable, Decodable {
    let patch: Int
    let major: Int
    let minor: Int
    
    init(map: Map) throws {
        patch = try map.value("patch")
        major = try map.value("major")
        minor = try map.value("minor")
    }
}

class Safe4CustomTokenRecord: Record, ImmutableMappable, Decodable, Identifiable {
    let address: String
    let symbol: String
    let creator: String
    let chainId: Int
    let decimals: Int
    let name: String
    var type: Int?
    var logoURI: String? = nil
    var version: String? = ""
    
    init(address: String, symbol: String, creator: String, chainId: Int, decimals: Int, name: String, type: Int? = nil, logoURI: String? = nil, version: String? = nil) {
        self.address = address
        self.symbol = symbol
        self.creator = creator
        self.chainId = chainId
        self.decimals = decimals
        self.name = name
        self.type = type
        self.logoURI = logoURI
        self.version = version
        super.init()
    }
    
    required init(map: Map) throws {
        address = try map.value("address")
        symbol = try map.value("symbol")
        creator = try map.value("creator")
        chainId = try map.value("chainId")
        decimals = try map.value("decimals")
        name = try map.value("name")
        type = try? map.value("type") ?? 0
        logoURI = try? map.value("logoURI")
        super.init()
    }
    
    var deployType: DeployType {
        if let type {
            return DeployType(rawValue: type)!
        }else {
            return getTypeForVersion()
        }
    }
    
    func getTypeForVersion() -> DeployType {
        if (version?.contains("SRC20-mintable") == true) {
            return .SRC20Mintable
        } else if (version?.contains("SRC20-burnable") == true) {
            return .SRC20Burnable
        } else {
            return .SRC20
        }
    }
    
    var canAdditionalIssuance: Bool {
        getTypeForVersion() == .SRC20Mintable || getTypeForVersion() == .SRC20Burnable
    }
    
    var canDestroy: Bool {
        getTypeForVersion() == .SRC20Burnable
    }
        
    override class var databaseTableName: String {
        "safe4_CustomToken"
    }

    enum Columns: String, ColumnExpression {
        case address, symbol, creator, chainId, decimals, name, type, logoURI, version
    }

    required init(row: Row) throws {
        address = row[Columns.address]
        symbol = row[Columns.symbol]
        creator = row[Columns.creator]
        chainId = row[Columns.chainId]
        decimals = row[Columns.decimals]
        name = row[Columns.name]
        type = row[Columns.type]
        logoURI = row[Columns.logoURI]
        version = row[Columns.version]
        try super.init(row: row)
    }

    override func encode(to container: inout PersistenceContainer) {
        container[Columns.address] = address
        container[Columns.symbol] = symbol
        container[Columns.creator] = creator
        container[Columns.chainId] = chainId
        container[Columns.decimals] = decimals
        container[Columns.name] = name
        container[Columns.type] = type
        container[Columns.logoURI] = logoURI
        container[Columns.version] = version
    }
}
