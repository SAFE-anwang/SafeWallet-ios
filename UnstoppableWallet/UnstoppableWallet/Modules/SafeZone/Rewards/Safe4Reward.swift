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
