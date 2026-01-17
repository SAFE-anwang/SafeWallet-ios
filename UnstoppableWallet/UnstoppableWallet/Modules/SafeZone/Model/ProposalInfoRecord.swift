import Foundation
import GRDB
import web3swift
import Web3Core
import BigInt

class ProposalInfoRecord: Record {
    var id: Int // BigUInt
    var creator: String // EthereumAddress
    var title: String
    var payAmount: String // BigUInt
    var payTimes: String // BigUInt
    var startPayTime: String // BigUInt
    var endPayTime: String // BigUInt
    var description: String
    var state: String // BigUInt
    var createHeight: String // BigUInt
    var updateHeight: String // BigUInt
    
    override class var databaseTableName: String {
        "proposal_info_record"
    }
    
    enum Columns: String, ColumnExpression {
        case id
        case creator
        case title
        case payAmount
        case payTimes
        case startPayTime
        case endPayTime
        case description
        case state
        case createHeight
        case updateHeight
    }
    
    required init(row: Row) throws {
            id = row[Columns.id]
            creator = row[Columns.creator]
            title = row[Columns.title]
            payAmount = row[Columns.payAmount]
            payTimes = row[Columns.payTimes]
            startPayTime = row[Columns.startPayTime]
            endPayTime = row[Columns.endPayTime]
            description = row[Columns.description]
            state = row[Columns.state]
            createHeight = row[Columns.createHeight]
            updateHeight = row[Columns.updateHeight]
            try super.init(row: row)
        }
        
    override func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.creator] = creator
        container[Columns.title] = title
        container[Columns.payAmount] = payAmount
        container[Columns.payTimes] = payTimes
        container[Columns.startPayTime] = startPayTime
        container[Columns.endPayTime] = endPayTime
        container[Columns.description] = description
        container[Columns.state] = state
        container[Columns.createHeight] = createHeight
        container[Columns.updateHeight] = updateHeight
    }
        
    init(id: Int, creator: String, title: String, payAmount: String, payTimes: String, startPayTime: String, endPayTime: String, description: String, state: String, createHeight: String, updateHeight: String) {
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
        super.init()
    }
    
    init(info: web3swift.ProposalInfo) {
        self.id = Int(info.id)
        self.creator = info.creator.address
        self.title = info.title
        self.payAmount = info.payAmount.description
        self.payTimes = info.payTimes.description
        self.startPayTime = info.startPayTime.description
        self.endPayTime = info.endPayTime.description
        self.description = info.description
        self.state = info.state.description
        self.createHeight = info.createHeight.description
        self.updateHeight = info.updateHeight.description
        super.init()
    }

    func transform() -> web3swift.ProposalInfo {
        return web3swift.ProposalInfo(id: BigUInt(id),
                                      creator: Web3Core.EthereumAddress(creator)!,
                                      title: title,
                                      payAmount: BigUInt(payAmount)!,
                                      payTime: BigUInt(payTimes)!,
                                      startPayTime: BigUInt(startPayTime)!,
                                      endPayTime: BigUInt(endPayTime)!,
                                      description: description,
                                      state: BigUInt(state)!,
                                      createHeight: BigUInt(createHeight)!,
                                      updateHeight: BigUInt(updateHeight)!
        )
    }
}
