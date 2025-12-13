import GRDB
import Foundation

class Redeem: Record {
    let address: String
    let existAvailable: Bool
    let existLocked: Bool
    let existMasterNode: Bool
    let success: Bool
    let lastRedeemTimestamp: TimeInterval
    
    init(address: String, existAvailable: Bool, existLocked: Bool, existMasterNode: Bool, success: Bool, lastRedeemTimestamp: TimeInterval) {
        self.address = address
        self.existAvailable = existAvailable
        self.existLocked = existLocked
        self.existMasterNode = existMasterNode
        self.success = success
        self.lastRedeemTimestamp = lastRedeemTimestamp
        super.init()
    }

    override class var databaseTableName: String {
        "safe3_redeem"
    }

    enum Columns: String, ColumnExpression {
        case address, existAvailable, existLocked, existMasterNode, success, lastRedeemTimestamp
    }

    required init(row: Row) throws {
        address = row[Columns.address]
        existAvailable = row[Columns.existAvailable]
        existLocked = row[Columns.existLocked]
        existMasterNode = row[Columns.existMasterNode]
        success = row[Columns.success]
        lastRedeemTimestamp = row[Columns.lastRedeemTimestamp]
        try super.init(row: row)
    }

    override func encode(to container: inout PersistenceContainer) {
        container[Columns.address] = address
        container[Columns.existAvailable] = existAvailable
        container[Columns.existLocked] = existLocked
        container[Columns.existMasterNode] = existMasterNode
        container[Columns.success] = success
        container[Columns.lastRedeemTimestamp] = lastRedeemTimestamp
    }
}
