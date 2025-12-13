import Foundation
import ObjectMapper
import web3swift
import Web3Core
import GRDB

class SuperNodeLockRecord: Record {
    var lockId: String
    var record: Safe4AccountRecord
    var info: Safe4RecordUseInfo?
    var isSuperNode: Bool
    var isVoted: Bool
    init(isSuperNode: Bool, isVoted: Bool, record: web3swift.AccountRecord, info: RecordUseInfo) {
        self.isSuperNode = isSuperNode
        self.isVoted = isVoted
        self.lockId = record.id.description
        self.record = Safe4AccountRecord(record: record)
        self.info = Safe4RecordUseInfo(info: info)
        super.init()
    }
    
    init(isSuperNode: Bool, isVoted: Bool, record: Safe4AccountRecord, info: Safe4RecordUseInfo?) {
        self.isSuperNode = isSuperNode
        self.isVoted = isVoted
        self.lockId = record.id.description
        self.record = record
        self.info = info
        super.init()
    }
    
    override class var databaseTableName: String {
        "Safe4_SuperNodeLockRecord"
    }

    enum Columns: String, ColumnExpression {
        case isSuperNode, isVoted, lockId, record, info
    }

    required init(row: Row) throws {
        isSuperNode = row[Columns.isSuperNode]
        isVoted = row[Columns.isVoted]
        record = try Safe4AccountRecord(JSONString: row[Columns.record])
        lockId = row[Columns.lockId]
        if let infoStr: String = row[Columns.info] {
            info = try Safe4RecordUseInfo(JSONString: infoStr)
        }
        try super.init(row: row)
    }

    override func encode(to container: inout PersistenceContainer) {
        container[Columns.isSuperNode] = isSuperNode
        container[Columns.isVoted] = isVoted
        container[Columns.lockId] = record.id.description
        container[Columns.record] = record.toJSONString()
        container[Columns.info] = info?.toJSONString()
    }
}
