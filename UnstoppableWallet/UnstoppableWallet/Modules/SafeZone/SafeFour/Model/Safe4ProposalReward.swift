import Foundation
import ObjectMapper
import web3swift
import Web3Core
import GRDB
import BigInt

class Safe4ProposalReward: Record {
    var lockId: String
    var ids: [Int]
    var info: Safe4ProposalInfo
    
    init(info: web3swift.ProposalInfo, ids: [BigUInt]) {
        self.lockId = info.id.description
        self.info = Safe4ProposalInfo(info: info)
        self.ids = ids.map{Int($0)}
        super.init()
    }
    
    init(info: Safe4ProposalInfo, ids: [Int]) {
        self.lockId = info.id.description
        self.info = info
        self.ids = ids
        super.init()
    }

    override class var databaseTableName: String {
        "Safe4_ProposalReward"
    }

    enum Columns: String, ColumnExpression {
        case lockId, ids, info
    }

    required init(row: Row) throws {
        let str: String = row[Columns.info]
        ids = str.split(separator: ",").compactMap { Int($0) }
        info = try Safe4ProposalInfo(JSONString: row[Columns.info])
        lockId = info.id.description
        try super.init(row: row)
    }

    override func encode(to container: inout PersistenceContainer) {
        container[Columns.lockId] = info.id.description
        container[Columns.ids] = ids.map(String.init).joined(separator: ",")
        container[Columns.info] = info.toJSONString()
    }
    
    private var idsString: String {
        get { ids.map(String.init).joined(separator: ",") }
        set { ids = newValue.split(separator: ",").compactMap { Int($0) } }
    }
}

class Safe4WithdrawProposalReward: Safe4ProposalReward {
    override class var databaseTableName: String {
        "Safe4_WithdrawProposalReward"
    }
}

class Safe4ProposalInfo: ImmutableMappable {
    var id: Int
    var creator: String
    var title: String
    var payAmount: String
    var payTimes: Int
    var startPayTime: Int
    var endPayTime: Int
    var description: String
    var state: Int
    var createHeight: String
    var updateHeight: String

    init(info: ProposalInfo) {
        self.id = Int(info.id)
        self.creator = info.creator.address
        self.title = info.title
        self.payAmount = info.payAmount.description
        self.payTimes = Int(info.payTimes)
        self.startPayTime = Int(info.startPayTime)
        self.endPayTime = Int(info.endPayTime)
        self.description = info.description
        self.state = Int(info.state)
        self.createHeight = info.createHeight.description
        self.updateHeight = info.updateHeight.description
    }
    
    init(id: Int, creator: String, title: String, payAmount: String, payTimes: Int, startPayTime: Int, endPayTime: Int, description: String, state: Int, createHeight: String, updateHeight: String) {
        self.id = id
        self.creator = creator
        self.title = title
        self.payAmount = payAmount
        self.payTimes = payTimes
        self.startPayTime = startPayTime
        self.endPayTime = endPayTime
        self.description = description
        self.state = state
        self.createHeight = createHeight
        self.updateHeight = updateHeight
    }

    required init(map: Map) throws {
        id = try map.value(Columns.id.rawValue)
        creator = try map.value(Columns.creator.rawValue)
        title = try map.value(Columns.title.rawValue)
        payAmount = try map.value(Columns.payAmount.rawValue)
        payTimes = try map.value(Columns.payTimes.rawValue)
        startPayTime = try map.value(Columns.startPayTime.rawValue)
        endPayTime = try map.value(Columns.endPayTime.rawValue)
        description = try map.value(Columns.description.rawValue)
        state = try map.value(Columns.state.rawValue)
        createHeight = try map.value(Columns.createHeight.rawValue)
        updateHeight = try map.value(Columns.updateHeight.rawValue)
    }

    func mapping(map: Map) {
        id >>> map[Columns.id.rawValue]
        creator >>> map[Columns.creator.rawValue]
        title >>> map[Columns.title.rawValue]
        payAmount >>> map[Columns.payAmount.rawValue]
        payTimes >>> map[Columns.payTimes.rawValue]
        startPayTime >>> map[Columns.startPayTime.rawValue]
        endPayTime >>> map[Columns.endPayTime.rawValue]
        description >>> map[Columns.description.rawValue]
        state >>> map[Columns.state.rawValue]
        createHeight >>> map[Columns.createHeight.rawValue]
        updateHeight >>> map[Columns.updateHeight.rawValue]
    }
    
    enum Columns: String {
        case id, creator, title, payAmount, payTimes, startPayTime, endPayTime, description, state, createHeight, updateHeight
    }
}
