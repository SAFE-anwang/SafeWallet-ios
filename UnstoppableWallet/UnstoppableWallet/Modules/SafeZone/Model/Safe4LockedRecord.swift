import Foundation
import ObjectMapper
import web3swift
import Web3Core
import GRDB

class Safe4LockedRecord: Record {
    var lockId: String
    var record: Safe4AccountRecord
    var info: Safe4RecordUseInfo?
    
    init(record: Safe4AccountRecord, info: Safe4RecordUseInfo?) {
        self.lockId = record.id.description
        self.record = record
        self.info = info
        super.init()
    }
    
    override class var databaseTableName: String {
        "Safe4_LockedRecord"
    }

    enum Columns: String, ColumnExpression {
        case lockId, record, info
    }

    required init(row: Row) throws {
        record = try Safe4AccountRecord(JSONString: row[Columns.record])
        lockId = row[Columns.lockId]
        if let infoStr: String = row[Columns.info] {
            info = try Safe4RecordUseInfo(JSONString: infoStr)
        }
        try super.init(row: row)
    }

    override func encode(to container: inout PersistenceContainer) {
        container[Columns.lockId] = record.id.description
        container[Columns.record] = record.toJSONString()
        container[Columns.info] = info?.toJSONString()
    }
}

class Safe4WithdrawLockedRecord: Record {
    var lockedType: Int
    var lockId: String
    var record: Safe4AccountRecord
    var info: Safe4RecordUseInfo?
    
    init(type: LockedRecordSourceType, record: Safe4AccountRecord, info: Safe4RecordUseInfo?) {
        self.lockedType = type.rawValue
        self.lockId = record.id.description
        self.record = record
        self.info = info
        super.init()
    }
    
    override class var databaseTableName: String {
        "Safe4_WithdrawLockedRecord"
    }

    enum Columns: String, ColumnExpression {
        case lockedType, lockId, record, info
    }

    required init(row: Row) throws {
        lockedType = row[Columns.lockedType]
        record = try Safe4AccountRecord(JSONString: row[Columns.record])
        lockId = record.id.description
        if let infoStr: String = row[Columns.info] {
            info = try Safe4RecordUseInfo(JSONString: infoStr)
        }
        try super.init(row: row)
    }

    override func encode(to container: inout PersistenceContainer) {
        container[Columns.lockedType] = lockedType
        container[Columns.lockId] = record.id.description
        container[Columns.record] = record.toJSONString()
        container[Columns.info] = info?.toJSONString()
    }
}

enum LockedRecordSourceType: Int {
    case locked
    case superNode
    case masterNode
    case voteLocked
    case proposal
}
