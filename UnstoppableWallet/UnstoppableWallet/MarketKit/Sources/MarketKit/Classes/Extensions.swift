import Foundation

extension Decimal {

    init?(convertibleValue: Any?) {
        guard let convertibleValue = convertibleValue as? CustomStringConvertible,
              let value = Decimal.init(string: convertibleValue.description) else {
            return nil
        }

        self = value
    }

}

extension TimeInterval {

    public static func minutes(_ count: Self) -> Self {
        count * 60
    }

    public static func hours(_ count: Self) -> Self {
        count * minutes(60)
    }

    public static func days(_ count: Self) -> Self {
        count * hours(24)
    }

}

extension CoinStorage {
    
    func insetSafeCoin(coins: [Coin]) -> [Coin] {
        let coinsStr = """
                        [{"uid":"safe-anwang","name":"SAFE(AnWang)", "code":"SAFE"}]
                       """
        guard let safeCoins = [Coin](JSONString: coinsStr)
        else {
            return coins
        }
        return safeCoins + coins
    }
    
    func insetSafeToken(tokens: [TokenRecord]) -> [TokenRecord] {
        let tokensStr = """
                        [{"coin_uid": "safe-anwang",
                         "blockchain_uid": "safe-anwang",
                         "decimals": 18,
                         "type": "native"
                         },
                        {"coin_uid": "safe-anwang",
                         "blockchain_uid": "ethereum",
                         "address": "0xee9c1ea4dcf0aaf4ff2d78b6ff83aa69797b65eb",
                         "decimals": 18,
                         "type": "eip20"
                        },
                        {"coin_uid": "safe-anwang",
                         "blockchain_uid": "binance-smart-chain",
                         "address": "0x4d7fa587ec8e50bd0e9cd837cb4da796f47218a1",
                         "decimals": 18,
                         "type": "eip20"}
                        ]
                        """
        guard let safeTokens = [TokenRecord](JSONString: tokensStr)
        else {
            return tokens
        }
        return safeTokens + tokens
    }
    
    func insetSafeBlockchain(blockchains: [BlockchainRecord]) -> [BlockchainRecord] {
        let blockchainStr = """
                            [{"uid":"safe-anwang","name":"SAFE(AnWang)","explorerUrl":"https://anwang.com/img/logos/safe.png"}]
                            """
        guard let safeBlockchainRecords = [BlockchainRecord](JSONString: blockchainStr)
        else {
            return blockchains
        }
        
        return safeBlockchainRecords + blockchains
    }

}
