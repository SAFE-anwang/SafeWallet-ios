import Foundation
import ObjectMapper
import BigInt

class Safe4Reward: ImmutableMappable {
    let amount: String
    let date: String
    
    required init(map: Map) throws {
        amount = try map.value("amount")
        date = try map.value("date")
    }
}

struct KLineWSafeTokenPriceModel: Codable, Identifiable, ImmutableMappable, Hashable {
    var id: String { address }
    
    let address: String
    let decimals: Int
    let name: String
    let symbol: String
    let price: String
    let change: String
    let logoURI: String
    let usdtReserves: String
    
    init(map: Map) throws {
        address = try map.value("address")
        decimals = try map.value("decimals")
        name = try map.value("name")
        symbol = try map.value("symbol")
        price = try map.value("price")
        change = try map.value("change")
        logoURI = try map.value("logoURI")
        usdtReserves = try map.value("usdtReserves")
    }
}
