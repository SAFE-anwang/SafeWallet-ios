import Foundation
import ObjectMapper
import MarketKit
import GRDB

class SafeCoinStorage {
    private let dbPool: DatabasePool
    
    init(dbPool: DatabasePool)  {
        self.dbPool = dbPool

        let coinsJsonStr = """
                            [
                                {"uid":"safe-anwang","name":"SAFE", "code":"SAFE"},
                           ]
                           """
        
        let blockchainsJsonStr = """
                                [
                                    {"uid":"safe-anwang","name":"SAFE","explorerUrl":"https://anwang.com/img/logos/safe.png"},
                                ]
                                """
        
        let tokensJsonStr = """
                            [   {"coin_uid":"safe-anwang","blockchain_uid":"safe-anwang","type":"native"},{"coin_uid":"safe-anwang","blockchain_uid":"ethereum","address":"0xee9c1ea4dcf0aaf4ff2d78b6ff83aa69797b65eb","decimals":8  ,"type":"eip20",},
                                {"coin_uid":"safe-anwang","blockchain_uid":"binance-smart-chain""address":"0x4d7fa587ec8e50bd0e9cd837cb4da796f47218a1","decimals":8,"type":"eip20",},
                            {"coin_uid": "safe-anwang",
                             "blockchain_uid": "polygon-pos",
                             "address": "0xb7Dd19490951339fE65E341Df6eC5f7f93FF2779",
                             "decimals": 18,
                             "type": "eip20"
                            }]
                            """
        
        guard let coins = [Coin](JSONString: coinsJsonStr) else {
            return
        }
        guard let blockchainRecords = [BlockchainRecord](JSONString: blockchainsJsonStr) else {
            return
        }
        guard let tokenRecords = [TokenRecord](JSONString: tokensJsonStr) else {
            return
        }
        do {
            try update(coins: coins, blockchainRecords: blockchainRecords, tokenRecords: tokenRecords)
        }catch {
            
        }
    }
    
    private func update(coins: [Coin], blockchainRecords: [BlockchainRecord], tokenRecords: [TokenRecord]) throws {
        _ = try dbPool.write { db in
            try Coin.deleteAll(db)
            try BlockchainRecord.deleteAll(db)
            try TokenRecord.deleteAll(db)

            for coin in coins {
                try coin.insert(db)
            }
            for blockchainRecord in blockchainRecords {
                try blockchainRecord.insert(db)
            }
            for tokenRecord in tokenRecords {
                try? tokenRecord.insert(db)
            }
        }
    }
}

fileprivate struct CoinTokensRecord: FetchableRecord, Decodable {
    let coin: Coin
    let tokens: [TokenBlockchainRecord]

    var fullCoin: FullCoin {
        FullCoin(
                coin: coin,
                tokens: tokens.map { record in
                    let tokenType: TokenType

                    if record.token.decimals != nil {
                        tokenType = TokenType(type: record.token.type, reference: record.token.reference)
                    } else {
                        tokenType = .unsupported(type: record.token.type, reference: record.token.reference)
                    }

                    return Token(
                            coin: coin,
                            blockchain: record.blockchain.blockchain,
                            type: tokenType,
                            decimals: record.token.decimals ?? 0
                    )
                }
        )
    }

}

fileprivate struct TokenBlockchainRecord: FetchableRecord, Decodable {
    let token: TokenRecord
    let blockchain: BlockchainRecord
}

fileprivate struct TokenInfoRecord: FetchableRecord, Decodable {
    let tokenRecord: TokenRecord
    let coin: Coin
    let blockchain: BlockchainRecord

    var token: Token {
        let tokenType: TokenType

        if tokenRecord.decimals != nil {
            tokenType = TokenType(type: tokenRecord.type, reference: tokenRecord.reference)
        } else {
            tokenType = .unsupported(type: tokenRecord.type, reference: tokenRecord.reference)
        }

        return Token(
                coin: coin,
                blockchain: blockchain.blockchain,
                type: tokenType,
                decimals: tokenRecord.decimals ?? 0
        )
    }

}



fileprivate class TokenRecord: Record, Decodable, ImmutableMappable {
    static let coin = belongsTo(Coin.self)
    static let blockchain = belongsTo(BlockchainRecord.self)

    let coinUid: String
    let blockchainUid: String
    let type: String
    let decimals: Int?
    let reference: String?

    override class var databaseTableName: String {
        "token"
    }

    enum Columns: String, ColumnExpression {
        case coinUid, blockchainUid, type, decimals, reference
    }

    init(coinUid: String, blockchainUid: String, type: String, decimals: Int? = nil, reference: String? = nil) {
        self.coinUid = coinUid
        self.blockchainUid = blockchainUid
        self.type = type
        self.decimals = decimals
        self.reference = reference

        super.init()
    }

    required init(map: Map) throws {
        let type: String = try map.value("type")

        coinUid = try map.value("coin_uid")
        blockchainUid = try map.value("blockchain_uid")
        self.type = type
        decimals = try? map.value("decimals")

        switch type {
        case "eip20": reference = try? map.value("address")
        case "bep2": reference = try? map.value("symbol")
        case "spl": reference = try? map.value("address")
        default: reference = try? map.value("address")
        }

        super.init()
    }

    func mapping(map: Map) {
        coinUid >>> map["coin_uid"]
        blockchainUid >>> map["blockchain_uid"]
        type >>> map["type"]
        decimals >>> map["decimals"]

        switch type {
        case "eip20": reference >>> map["address"]
        case "bep2": reference >>> map["symbol"]
        case "spl": reference >>> map["address"]
        case "unsupported":
            if let reference = reference {
                reference >>> map["address"]
            }
        default: ()
        }
    }

    required init(row: Row) {
        coinUid = row[Columns.coinUid]
        blockchainUid = row[Columns.blockchainUid]
        type = row[Columns.type]
        decimals = row[Columns.decimals]
        reference = row[Columns.reference]

        super.init(row: row)
    }

    override func encode(to container: inout PersistenceContainer) {
        container[Columns.coinUid] = coinUid
        container[Columns.blockchainUid] = blockchainUid
        container[Columns.type] = type
        container[Columns.decimals] = decimals
        container[Columns.reference] = reference
    }

}

fileprivate class BlockchainRecord: Record, Decodable, ImmutableMappable {
    static let tokens = hasMany(TokenRecord.self)

    let uid: String
    let name: String
    let explorerUrl: String?

    override class var databaseTableName: String {
        "blockchain"
    }

    enum Columns: String, ColumnExpression {
        case uid, name, explorerUrl
    }

    required init(map: Map) throws {
        uid = try map.value("uid")
        name = try map.value("name")
        explorerUrl = try? map.value("url")

        super.init()
    }

    func mapping(map: Map) {
        uid >>> map["uid"]
        name >>> map["name"]
        explorerUrl >>> map["url"]
    }

    required init(row: Row) {
        uid = row[Columns.uid]
        name = row[Columns.name]
        explorerUrl = row[Columns.explorerUrl]

        super.init(row: row)
    }

    override func encode(to container: inout PersistenceContainer) {
        container[Columns.uid] = uid
        container[Columns.name] = name
        container[Columns.explorerUrl] = explorerUrl
    }

    var blockchain: Blockchain {
        Blockchain(
                type: BlockchainType(uid: uid),
                name: name,
                eip3091url: explorerUrl
        )
    }

}
