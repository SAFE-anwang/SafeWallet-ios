import Foundation
import ObjectMapper
import web3swift
import Web3Core
import BigInt

struct Safe4AccountRecord: ImmutableMappable {
    var type: Int = 0
    var id: Int // BigUInt
    var address: String
    var amount: String // BigUInt
    var lockDay: String // BigUInt
    var startHeight: String // BigUInt
    var unlockHeight: String // BigUInt
    
    init(map: Map) throws {
        id = try map.value("id")
        address = try map.value("address")
        amount = try map.value("amount")
        lockDay = try map.value("lockDay")
        startHeight = try map.value("startHeight")
        unlockHeight = try map.value("unlockHeight")
    }

    func mapping(map: Map) {
        id >>> map["id"]
        address >>> map["address"]
        amount >>> map["amount"]
        lockDay >>> map["lockDay"]
        startHeight >>> map["startHeight"]
        unlockHeight >>> map["unlockHeight"]
    }
    
    init(type: Int, id: Int, address: String, amount: String, lockDay: String, startHeight: String, unlockHeight: String) {
        self.type = type
        self.id = id
        self.address = address
        self.amount = amount
        self.lockDay = lockDay
        self.startHeight = startHeight
        self.unlockHeight = unlockHeight
    }
    
    init(record: web3swift.AccountRecord) {
        self.id = Int(record.id)
        self.address = record.addr.address
        self.amount = record.amount.description
        self.lockDay = record.lockDay.description
        self.startHeight = record.startHeight.description
        self.unlockHeight = record.unlockHeight.description
    }
    
    func transform() -> web3swift.AccountRecord {
        let address = Web3Core.EthereumAddress(address)!
        return web3swift.AccountRecord(id: BigUInt(id),
                                       addr: address,
                                       amount: BigUInt(amount)!,
                                       lockDay: BigUInt(lockDay)!,
                                       startHeight: BigUInt(startHeight)!,
                                       unlockHeight: BigUInt(unlockHeight)!)
    }

    enum Columns: String {
        case type, id, address, amount, unlockHeight, startHeight, lockDay
    }
}
