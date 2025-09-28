import Foundation
import ObjectMapper
import web3swift
import Web3Core
import BigInt

struct Safe4RecordUseInfo: ImmutableMappable {
    public var frozenAddr: String
    public var freezeHeight: String // BigUInt
    public var unfreezeHeight: String // BigUInt
    public var votedAddr: String
    public var voteHeight: String // BigUInt
    public var releaseHeight: String // BigUInt
    
    init(map: Map) throws {
        frozenAddr = try map.value(Columns.frozenAddr.rawValue)
        freezeHeight = try map.value(Columns.freezeHeight.rawValue)
        unfreezeHeight = try map.value(Columns.unfreezeHeight.rawValue)
        votedAddr = try map.value(Columns.votedAddr.rawValue)
        voteHeight = try map.value(Columns.voteHeight.rawValue)
        releaseHeight = try map.value(Columns.releaseHeight.rawValue)
    }

    func mapping(map: Map) {
        frozenAddr >>> map[Columns.frozenAddr.rawValue]
        freezeHeight >>> map[Columns.freezeHeight.rawValue]
        unfreezeHeight >>> map[Columns.unfreezeHeight.rawValue]
        votedAddr >>> map[Columns.votedAddr.rawValue]
        voteHeight >>> map[Columns.voteHeight.rawValue]
        releaseHeight >>> map[Columns.releaseHeight.rawValue]
    }
    
    init(info: web3swift.RecordUseInfo) {
        self.frozenAddr = info.frozenAddr.address
        self.freezeHeight = info.freezeHeight.description
        self.unfreezeHeight = info.unfreezeHeight.description
        self.votedAddr = info.votedAddr.address
        self.voteHeight = info.voteHeight.description
        self.releaseHeight = info.releaseHeight.description
    }
    
    func transform() -> web3swift.RecordUseInfo {
        let frozenAddr = Web3Core.EthereumAddress(frozenAddr)!
        let votedAddr = Web3Core.EthereumAddress(votedAddr)!
        return web3swift.RecordUseInfo(frozenAddr: frozenAddr,
                                       freezeHeight: BigUInt(freezeHeight)!,
                                       unfreezeHeight: BigUInt(unfreezeHeight)!,
                                       votedAddr: votedAddr,
                                       voteHeight: BigUInt(voteHeight)!,
                                       releaseHeight: BigUInt(releaseHeight)!)
    }
    
    enum Columns: String {
        case frozenAddr, freezeHeight, unfreezeHeight, votedAddr, voteHeight, releaseHeight
    }
}
