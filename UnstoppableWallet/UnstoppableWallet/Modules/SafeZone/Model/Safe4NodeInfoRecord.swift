import Foundation
import ObjectMapper
import web3swift
import Web3Core
import GRDB
import BigInt
//class Safe4SuperNodeRecord: Record, Codable {
//    var id: Int64?
//    var infoId: Int64?
//    var info: Safe4NodeInfo
//    var totalVoteNum: String // BigUInt
//    var totalAmount: String // BigUInt
//    var allVoteNum: String // BigUInt
//    
//    static let nodeInfo = belongsTo(Safe4NodeInfo.self)
//    
//    override class var databaseTableName: String {
//        "Safe4_SuperNodeRecord"
//    }
//
//    enum Columns: String, ColumnExpression {
//        case id, infoId, info, totalVoteNum, totalAmount, allVoteNum
//    }
//
//}
//extension Safe4NodeInfo: DatabaseValueConvertible {
//    
//}

class Safe4NodeInfo: Record, Codable {
    var recordId: Int64
    var displayOrder: Int?
    var id: String // BigUInt
    var name: String
    var addr: String// EthereumAddress
    var creator: String// EthereumAddress
    var enode: String
    var description: String
    var isOfficial: Bool
    var state: String // BigUInt
    var founders: [NodeMemberInfo]
    var incentivePlan: NodeIncentivePlan?
    var isUnion: Bool
    var lastRewardHeight: String // BigUInt
    var createHeight: String // BigUInt
    var updateHeight: String // BigUInt
    var totalVoteNum: String?
    var totalAmount: String?
    var allVoteNum: String?
        
    override class var databaseTableName: String {
        "Safe4_Safe4NodeInfo"
    }
//    static let superNodeRecord = hasOne(Safe4SuperNodeRecord.self)
    
    enum Columns: String, ColumnExpression {
        case recordId, displayOrder, id, name, addr, creator, enode, description, isOfficial, state, founders, incentivePlan, isUnion, lastRewardHeight, createHeight, updateHeight, totalVoteNum, totalAmount, allVoteNum
    }
    
    required init(row: Row) throws {
        recordId = row[Columns.recordId]
        displayOrder = row[Columns.displayOrder]
        id = row[Columns.id]
        name = row[Columns.name]
        addr = row[Columns.addr]
        creator = row[Columns.creator]
        enode = row[Columns.enode]
        description = row[Columns.description]
        isOfficial = row[Columns.isOfficial]
        state = row[Columns.state]
        if let foundersData: String = row[Columns.founders], let founders = try? JSONDecoder().decode([NodeMemberInfo].self, from: Data(foundersData.utf8)) {
            self.founders = founders
        } else {
            self.founders = []
        }
        
        if let incentivePlanData: String = row[Columns.incentivePlan], let incentivePlan = try? JSONDecoder().decode(NodeIncentivePlan.self, from: Data(incentivePlanData.utf8)) {
            self.incentivePlan = incentivePlan
        }else {
            self.incentivePlan = nil
        }
        isUnion = row[Columns.isUnion]
        lastRewardHeight = row[Columns.lastRewardHeight]
        createHeight = row[Columns.createHeight]
        updateHeight = row[Columns.updateHeight]
        totalVoteNum = row[Columns.totalVoteNum]
        totalAmount = row[Columns.totalAmount]
        allVoteNum = row[Columns.allVoteNum]

        try super.init(row: row)
    }

    override func encode(to container: inout PersistenceContainer) {
        container[Columns.recordId] = recordId
        container[Columns.displayOrder] = displayOrder
        container[Columns.id] = id.description
        container[Columns.name] = name
        container[Columns.addr] = addr
        container[Columns.creator] = creator
        container[Columns.enode] = enode
        container[Columns.description] = description
        container[Columns.isOfficial] = isOfficial
        container[Columns.state] = state
        if let foundersJSON = try? JSONEncoder().encode(founders), let founders = String(data: foundersJSON, encoding: .utf8) {
            container[Columns.founders] = founders
        }else {
            container[Columns.founders] = ""
        }
        
        if let incentivePlanJSON = try? JSONEncoder().encode(incentivePlan), let incentivePlan = String(data: incentivePlanJSON, encoding: .utf8) {
            container[Columns.incentivePlan] = incentivePlan
        }
        container[Columns.isUnion] = isUnion
        container[Columns.lastRewardHeight] = lastRewardHeight
        container[Columns.createHeight] = createHeight
        container[Columns.updateHeight] = updateHeight
        container[Columns.totalVoteNum] = totalVoteNum
        container[Columns.totalAmount] = totalAmount
        container[Columns.allVoteNum] = allVoteNum
    }
        
    init(recordId: Int64, _ record: web3swift.SuperNodeInfo, totalVoteNum: BigUInt? = nil, totalAmount: BigUInt? = nil, allVoteNum: BigUInt? = nil) {
        self.recordId = recordId
        self.displayOrder = nil
        self.id = record.id.description
        self.name = record.name
        self.addr = record.addr.address
        self.creator = record.creator.address
        self.enode = record.enode
        self.description = record.description
        self.isOfficial = record.isOfficial
        self.state = record.state.description
        self.founders = record.founders.map {
            NodeMemberInfo(lockID: $0.lockID.description,
                           addr: $0.addr.address,
                           amount: $0.amount.description,
                           unlockHeight: $0.unlockHeight.description
            )
        }
        self.incentivePlan = NodeIncentivePlan(
            creator: record.incentivePlan.creator.description,
            partner: record.incentivePlan.partner.description,
            voter: record.incentivePlan.voter.description)

        self.isUnion = record.isUnion
        self.lastRewardHeight = record.lastRewardHeight.description
        self.createHeight = record.createHeight.description
        self.updateHeight = record.updateHeight.description
        self.totalVoteNum = totalVoteNum?.description
        self.totalAmount = totalAmount?.description
        self.allVoteNum = allVoteNum?.description
        super.init()
    }
    
    init(recordId: Int64, _ record: web3swift.MasterNodeInfo) {
        self.recordId = recordId
        self.displayOrder = nil
        self.id = record.id.description
        self.name = ""
        self.addr = record.addr.address
        self.creator = record.creator.address
        self.enode = record.enode
        self.description = record.description
        self.isOfficial = record.isOfficial
        self.state = record.state.description
        self.founders = record.founders.map {
            NodeMemberInfo(lockID: $0.lockID.description,
                           addr: $0.addr.address,
                           amount: $0.amount.description,
                           unlockHeight: $0.unlockHeight.description
            )
        }
        self.incentivePlan = NodeIncentivePlan(
            creator: record.incentivePlan.creator.description,
            partner: record.incentivePlan.partner.description,
            voter: record.incentivePlan.voter.description)
    
        self.isUnion = record.isUnion
        self.lastRewardHeight = record.lastRewardHeight.description
        self.createHeight = record.createHeight.description
        self.updateHeight = record.updateHeight.description
        self.totalVoteNum = nil
        self.totalAmount = nil
        self.allVoteNum = nil
        super.init()
    }

    func transformToSuper() -> web3swift.SuperNodeInfo {
        return web3swift.SuperNodeInfo(id: BigUInt(id)!,
                                       name: name,
                                       addr: Web3Core.EthereumAddress(addr)!,
                                       creator: Web3Core.EthereumAddress(creator)!,
                                       enode: enode,
                                       description: description,
                                       isOfficial: isOfficial,
                                       state: BigUInt(state)!,
                                       founders: founders.map{$0.transformToSuper()},
                                       incentivePlan: incentivePlan!.transformToSuper(),
                                       isUnion: isUnion,
                                       lastRewardHeight: BigUInt(lastRewardHeight)!,
                                       createHeight: BigUInt(createHeight)!,
                                       updateHeight: BigUInt(updateHeight)!)
    }
    
    func transformToMaster() -> web3swift.MasterNodeInfo {
        return web3swift.MasterNodeInfo(id: BigUInt(id)!,
                                        addr: Web3Core.EthereumAddress(addr)!,
                                        creator: Web3Core.EthereumAddress(creator)!,
                                        enode: enode,
                                        description: description,
                                        isOfficial: isOfficial,
                                        state: BigUInt(state)!,
                                        founders: founders.map{$0.transformToMaster()},
                                        incentivePlan: incentivePlan!.transformToMaster(),
                                        isUnion: isUnion,
                                        lastRewardHeight: BigUInt(lastRewardHeight)!,
                                        createHeight: BigUInt(createHeight)!,
                                        updateHeight: BigUInt(updateHeight)!)
    }
}

struct NodeMemberInfo: Codable, ImmutableMappable {
    var lockID: String// BigUInt
    var addr: String// EthereumAddress
    var amount: String// BigUInt
    var unlockHeight: String// BigUInt
    
    init(lockID: String, addr: String, amount: String, unlockHeight: String) {
        self.lockID = lockID
        self.addr = addr
        self.amount = amount
        self.unlockHeight = unlockHeight
    }
    
    init(map: Map) throws {
        lockID = try map.value("lockID")
        addr = try map.value("addr")
        amount = try map.value("amount")
        unlockHeight = try map.value("unlockHeight")
    }

    func mapping(map: Map) {
        lockID >>> map["lockID"]
        addr >>> map["addr"]
        amount >>> map["amount"]
        unlockHeight >>> map["unlockHeight"]
    }
    
    func transformToSuper() -> web3swift.SuperNodeMemberInfo {
        web3swift.SuperNodeMemberInfo(lockID: BigUInt(lockID)!,
                                      addr: Web3Core.EthereumAddress(addr)!,
                                      amount: BigUInt(amount)!,
                                      unlockHeight: BigUInt(unlockHeight)!
        )
    }
    
    func transformToMaster() -> web3swift.MasterNodeMemberInfo {
        web3swift.MasterNodeMemberInfo(lockID: BigUInt(lockID)!,
                                      addr: Web3Core.EthereumAddress(addr)!,
                                      amount: BigUInt(amount)!,
                                      unlockHeight: BigUInt(unlockHeight)!
        )
    }
}

struct NodeIncentivePlan: Codable, ImmutableMappable {
    var creator: String// BigUInt
    var partner: String// BigUInt
    var voter: String// BigUInt
    init(creator: String, partner: String, voter: String) {
        self.creator = creator
        self.partner = partner
        self.voter = voter
    }
    
    init(map: Map) throws {
        creator = try map.value("creator")
        partner = try map.value("partner")
        voter = try map.value("voter")
    }

    func mapping(map: Map) {
        creator >>> map["creator"]
        partner >>> map["partner"]
        voter >>> map["voter"]
    }
    
    func transformToSuper() -> web3swift.SuperNodeIncentivePlan {
        web3swift.SuperNodeIncentivePlan(creator: BigUInt(creator)!,
                                         partner: BigUInt(partner)!,
                                         voter: BigUInt(voter)!)
    }
    
    func transformToMaster() -> web3swift.MasterNodeIncentivePlan {
        web3swift.MasterNodeIncentivePlan(creator: BigUInt(creator)!,
                                         partner: BigUInt(partner)!,
                                         voter: BigUInt(voter)!)
    }
}
