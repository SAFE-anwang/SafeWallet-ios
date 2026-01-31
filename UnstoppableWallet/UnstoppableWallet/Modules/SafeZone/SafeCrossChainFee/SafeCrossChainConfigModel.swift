import Foundation
import ObjectMapper

// SAFE4 
class CrossChainSafe4NativeConfig: ImmutableMappable {
    var safe_usdt: Double
    var minamount: Double
    var eth: EthChainInfo?
    var bsc: BscChainInfo?
    var matic: MaticChainInfo?
    
    required init(map: Map) throws {
        
        safe_usdt = try map.value("safe_usdt")
        minamount = try map.value("minamount")
        eth = try? map.value("eth")
        bsc = try? map.value("bsc")
        matic = try? map.value("matic")
    }
    
    func mapping(map: Map) {
         safe_usdt >>> map["safe_usdt"]
         minamount >>> map["minamount"]
         eth       >>> map["eth"]
         bsc       >>> map["bsc"]
         matic     >>> map["matic"]
    }
    
    init(safe_usdt: Double, minamount: Double, eth: EthChainInfo?, bsc: BscChainInfo?, matic: MaticChainInfo?) {
        self.safe_usdt = safe_usdt
        self.minamount = minamount
        self.eth = eth
        self.bsc = bsc
        self.matic = matic
    }
    
    class EthChainInfo: ImmutableMappable {
        var price: Double
        var gas_price_gwei: Double
        var safe_fee: Double
        var safe2eth: Bool
        var eth2safe: Bool
        
        required init(map: Map) throws {
            price = try map.value("price")
            gas_price_gwei = try map.value("gas_price_gwei")
            safe_fee = try map.value("safe_fee")
            safe2eth = try map.value("safe2eth")
            eth2safe = try map.value("eth2safe")
        }
        
        func mapping(map: Map) {
            price          >>> map["price"]
            gas_price_gwei >>> map["gas_price_gwei"]
            safe_fee       >>> map["safe_fee"]
            safe2eth       >>> map["safe2eth"]
            eth2safe       >>> map["eth2safe"]
       }
        
        init(price: Double, gas_price_gwei: Double, safe_fee: Double, safe2eth: Bool, eth2safe: Bool) {
            self.price = price
            self.gas_price_gwei = gas_price_gwei
            self.safe_fee = safe_fee
            self.safe2eth = safe2eth
            self.eth2safe = eth2safe
        }
    }
    
    class BscChainInfo: ImmutableMappable {
        let price: Double
        let gas_price_gwei: Double
        let safe_fee: Double
        let safe2bsc: Bool
        let bsc2safe: Bool
        
        required init(map: Map) throws {
            price = try map.value("price")
            gas_price_gwei = try map.value("gas_price_gwei")
            safe_fee = try map.value("safe_fee")
            safe2bsc = try map.value("safe2bsc")
            bsc2safe = try map.value("bsc2safe")
        }
        
        func mapping(map: Map) {
            price          >>> map["price"]
            gas_price_gwei >>> map["gas_price_gwei"]
            safe_fee       >>> map["safe_fee"]
            safe2bsc       >>> map["safe2bsc"]
            bsc2safe       >>> map["bsc2safe"]
        }
        
        init(price: Double, gas_price_gwei: Double, safe_fee: Double, safe2bsc: Bool, bsc2safe: Bool) {
            self.price = price
            self.gas_price_gwei = gas_price_gwei
            self.safe_fee = safe_fee
            self.safe2bsc = safe2bsc
            self.bsc2safe = bsc2safe
        }

    }

    class MaticChainInfo: ImmutableMappable {
        let price: Double
        let gas_price_gwei: Double
        let safe_fee: Double
        let safe2matic: Bool
        let matic2safe: Bool
        
        required init(map: Map) throws {
            price = try map.value("price")
            gas_price_gwei = try map.value("gas_price_gwei")
            safe_fee = try map.value("safe_fee")
            safe2matic = try map.value("safe2matic")
            matic2safe = try map.value("matic2safe")
        }
        
        func mapping(map: Map) {
            price          >>> map["price"]
            gas_price_gwei >>> map["gas_price_gwei"]
            safe_fee       >>> map["safe_fee"]
            safe2matic     >>> map["safe2matic"]
            matic2safe     >>> map["matic2safe"]
        }

        init(price: Double, gas_price_gwei: Double, safe_fee: Double, safe2matic: Bool, matic2safe: Bool) {
            self.price = price
            self.gas_price_gwei = gas_price_gwei
            self.safe_fee = safe_fee
            self.safe2matic = safe2matic
            self.matic2safe = matic2safe
        }
    }
}

// USDT
class CrossChainSafe4USDTConfig: ImmutableMappable {
    var safe_usdt: Double
    var minamount: Double
    var eth: EthChainInfo?
    var bsc: BscChainInfo?
    var sol: SolChainInfo?
    var trx: TrxChainInfo?
    
    required init(map: Map) throws {
        safe_usdt = try map.value("safe_usdt")
        minamount = try map.value("minamount")
        eth = try? map.value("eth")
        bsc = try? map.value("bsc")
        sol = try? map.value("sol")
        trx = try? map.value("trx")
    }
    
    func mapping(map: Map) {
        safe_usdt >>> map["safe_usdt"]
        minamount >>> map["minamount"]
        eth       >>> map["eth"]
        bsc       >>> map["bsc"]
        sol       >>> map["sol"]
        trx       >>> map["trx"]
    }
    
    init(safe_usdt: Double, minamount: Double, eth: EthChainInfo? = nil, bsc: BscChainInfo? = nil, sol: SolChainInfo? = nil, trx: TrxChainInfo? = nil) {
        self.safe_usdt = safe_usdt
        self.minamount = minamount
        self.eth = eth
        self.bsc = bsc
        self.sol = sol
        self.trx = trx
    }
    
    class EthChainInfo: ImmutableMappable {
        var price: Double
        var gas_price_gwei: Double
        var usdt_fee: Double
        var safe2eth: Bool
        var eth2safe: Bool
        
        required init(map: Map) throws {
            price = try map.value("price")
            gas_price_gwei = try map.value("gas_price_gwei")
            usdt_fee = try map.value("usdt_fee")
            safe2eth = try map.value("safe2eth")
            eth2safe = try map.value("eth2safe")
        }
        
        func mapping(map: Map) {
            price          >>> map["price"]
            gas_price_gwei >>> map["gas_price_gwei"]
            usdt_fee       >>> map["usdt_fee"]
            safe2eth       >>> map["safe2eth"]
            eth2safe       >>> map["eth2safe"]
       }
        
        init(price: Double, gas_price_gwei: Double, usdt_fee: Double, safe2eth: Bool, eth2safe: Bool) {
            self.price = price
            self.gas_price_gwei = gas_price_gwei
            self.usdt_fee = usdt_fee
            self.safe2eth = safe2eth
            self.eth2safe = eth2safe
        }
    }

    class BscChainInfo: ImmutableMappable {
        let price: Double
        let gas_price_gwei: Double
        let usdt_fee: Double
        let safe2bsc: Bool
        let bsc2safe: Bool
        
        required init(map: Map) throws {
            price = try map.value("price")
            gas_price_gwei = try map.value("gas_price_gwei")
            usdt_fee = try map.value("usdt_fee")
            safe2bsc = try map.value("safe2bsc")
            bsc2safe = try map.value("bsc2safe")
        }
        
        func mapping(map: Map) {
            price          >>> map["price"]
            gas_price_gwei >>> map["gas_price_gwei"]
            usdt_fee       >>> map["usdt_fee"]
            safe2bsc       >>> map["safe2bsc"]
            bsc2safe       >>> map["bsc2safe"]
        }
        
        init(price: Double, gas_price_gwei: Double, usdt_fee: Double, safe2bsc: Bool, bsc2safe: Bool) {
            self.price = price
            self.gas_price_gwei = gas_price_gwei
            self.usdt_fee = usdt_fee
            self.safe2bsc = safe2bsc
            self.bsc2safe = bsc2safe
        }
    }
    
    class TrxChainInfo: ImmutableMappable {
        let price: Double
        let gas_price_gwei: Double
        let usdt_fee: Double
        let safe2trx: Bool
        let trx2safe: Bool
        
        init(price: Double, gas_price_gwei: Double, usdt_fee: Double, safe2trx: Bool, trx2safe: Bool) {
            self.price = price
            self.gas_price_gwei = gas_price_gwei
            self.usdt_fee = usdt_fee
            self.safe2trx = safe2trx
            self.trx2safe = trx2safe
        }
        
        required init(map: Map) throws {
            price = try map.value("price")
            gas_price_gwei = try map.value("gas_price_gwei")
            usdt_fee = try map.value("usdt_fee")
            safe2trx = try map.value("safe2trx")
            trx2safe = try map.value("trx2safe")
        }
        
        func mapping(map: Map) {
            price          >>> map["price"]
            gas_price_gwei >>> map["gas_price_gwei"]
            usdt_fee       >>> map["usdt_fee"]
            safe2trx     >>> map["safe2trx"]
            trx2safe     >>> map["trx2safe"]
        }
    }
    class SolChainInfo: ImmutableMappable {
        let price: Double
        let gas_price_gwei: Double
        let usdt_fee: Double
        let safe2sol: Bool
        let sol2safe: Bool
        
        init(price: Double, gas_price_gwei: Double, usdt_fee: Double, safe2sol: Bool, sol2safe: Bool) {
            self.price = price
            self.gas_price_gwei = gas_price_gwei
            self.usdt_fee = usdt_fee
            self.safe2sol = safe2sol
            self.sol2safe = sol2safe
        }
        
        required init(map: Map) throws {
            price = try map.value("price")
            gas_price_gwei = try map.value("gas_price_gwei")
            usdt_fee = try map.value("usdt_fee")
            safe2sol = try map.value("safe2sol")
            sol2safe = try map.value("sol2safe")
        }
        
        func mapping(map: Map) {
            price          >>> map["price"]
            gas_price_gwei >>> map["gas_price_gwei"]
            usdt_fee       >>> map["usdt_fee"]
            safe2sol     >>> map["safe2sol"]
            sol2safe     >>> map["sol2safe"]
        }
    }
}
