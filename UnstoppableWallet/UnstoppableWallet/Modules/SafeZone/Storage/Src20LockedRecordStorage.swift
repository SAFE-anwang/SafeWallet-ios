import Foundation
import GRDB
import web3swift
import Web3Core
import BigInt

class Src20AllTokenLockedRecordStorage {
    private let dbPool: DatabasePool

    init(dbPool: DatabasePool) throws {
        self.dbPool = dbPool
        try migrator.migrate(dbPool)
    }
    var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        
        migrator.registerMigration("create Src20AllTokenLockedRecordStorage") { db in
            
            try db.create(table: Src20AllTokenLockedsRecord.databaseTableName) { t in
                t.column(Src20AllTokenLockedsRecord.Columns.tokenContract.name, .text).notNull().indexed()
                t.primaryKey([Src20AllTokenLockedsRecord.Columns.tokenContract.name], onConflict: .replace)
            }
            
            try db.create(table: Src20TokenLockedRecord.databaseTableName) { t in
                t.column(Src20TokenLockedRecord.Columns.id.name, .integer).notNull()
                t.column(Src20TokenLockedRecord.Columns.tokenContract.name, .text).notNull().indexed()
                t.column(Src20TokenLockedRecord.Columns.addr.name, .text).notNull()
                t.column(Src20TokenLockedRecord.Columns.amount.name, .text).notNull()
                t.column(Src20TokenLockedRecord.Columns.lockDay.name, .integer).notNull()
                t.column(Src20TokenLockedRecord.Columns.startHeight.name, .integer).notNull()
                t.column(Src20TokenLockedRecord.Columns.unlockHeight.name, .integer).notNull()
                t.primaryKey([Src20TokenLockedRecord.Columns.id.name, Src20TokenLockedRecord.Columns.addr.name], onConflict: .replace)
                t.foreignKey([Src20TokenLockedRecord.Columns.tokenContract.name], references: Src20AllTokenLockedsRecord.databaseTableName, onDelete: .cascade)
            }
        }
        return migrator
    }
}

extension Src20AllTokenLockedRecordStorage {
    func allTokens() throws -> [Src20AllTokenLockedsRecord] {
        try dbPool.read { db in
            try Src20AllTokenLockedsRecord.fetchAll(db)
        }
    }

    func tokenRecords(tokenContract: String) throws -> [Src20TokenLockedRecord] {
        try dbPool.read { db in
            try Src20TokenLockedRecord
                .filter(Src20TokenLockedRecord.Columns.tokenContract.lowercased == tokenContract.lowercased())
                .fetchAll(db)
        }
    }

    func save(recoards: [Src20TokenLockedRecord]) {
        for recoard in recoards {
            save(recoard: recoard)
        }
    }

    func save(recoard: Src20TokenLockedRecord) {
        _ = try? dbPool.write { db in
            if try Src20AllTokenLockedsRecord
                .filter(Src20AllTokenLockedsRecord.Columns.tokenContract == recoard.tokenContract.lowercased())
                .fetchOne(db) == nil {
                try Src20AllTokenLockedsRecord(tokenContract: recoard.tokenContract).insert(db)
            }

            let existing = try Src20TokenLockedRecord
                .filter(Src20TokenLockedRecord.Columns.id == recoard.id)
                .filter(Src20TokenLockedRecord.Columns.addr == recoard.addr)
                .fetchOne(db)

            if existing == nil {
                try recoard.insert(db)
            } else {
                try recoard.update(db)
            }
        }
    }

    func update(recoard: Src20TokenLockedRecord) {
        _ = try? dbPool.write { db in
            try recoard.update(db)
        }
    }

    func delete(tokenContract: String) {
        _ = try? dbPool.write { db in
            try Src20AllTokenLockedsRecord
                .filter(Src20AllTokenLockedsRecord.Columns.tokenContract.lowercased == tokenContract.lowercased())
                .deleteAll(db)
        }
    }

    func delete(id: Int, addr: String) {
        _ = try? dbPool.write { db in
            try Src20TokenLockedRecord
                .filter(Src20TokenLockedRecord.Columns.id == id)
                .filter(Src20TokenLockedRecord.Columns.addr == addr)
                .deleteAll(db)
        }
    }

    func clear() throws {
        _ = try dbPool.write { db in
            try Src20TokenLockedRecord.deleteAll(db)
            try Src20AllTokenLockedsRecord.deleteAll(db)
        }
    }
}

class Src20AllTokenLockedsRecord: Record {
    var tokenContract: String
    static let records = hasMany(Src20TokenLockedRecord.self)

    override class var databaseTableName: String {
        "Src20_All_Token_Lockeds_Record"
    }

    enum Columns: String, ColumnExpression {
        case tokenContract
    }

    init(tokenContract: String) {
        self.tokenContract = tokenContract
        super.init()
    }

    required init(row: Row) throws {
        tokenContract = row[Columns.tokenContract]
        try super.init(row: row)
    }

    override func encode(to container: inout PersistenceContainer) throws {
        container[Columns.tokenContract] = tokenContract
    }
}

class Src20TokenLockedRecord: Record {
    var id: Int
    var tokenContract: String
    var addr: String
    var amount: String
    var lockDay: Int
    var startHeight: Int
    var unlockHeight: Int
    
    static let parent = belongsTo(
        Src20AllTokenLockedsRecord.self,
        using: ForeignKey([Columns.tokenContract.name])
    )
    
    init(
        id: Int,
        tokenContract: String,
        addr: String,
        amount: String,
        lockDay: Int,
        startHeight: Int,
        unlockHeight: Int
    ) {
        self.id = id
        self.tokenContract = tokenContract
        self.addr = addr
        self.amount = amount
        self.lockDay = lockDay
        self.startHeight = startHeight
        self.unlockHeight = unlockHeight
        super.init()
    }
    
    override class var databaseTableName: String {
        "Src20_Locked_Record"
    }
    
    enum Columns: String, ColumnExpression {
        case id
        case tokenContract
        case addr
        case amount
        case lockDay
        case startHeight
        case unlockHeight
    }
    
    required init(row: Row) throws {
        id = row[Columns.id]
        tokenContract = row[Columns.tokenContract]
        addr = row[Columns.addr]
        amount = row[Columns.amount]
        lockDay = row[Columns.lockDay]
        startHeight = row[Columns.startHeight]
        unlockHeight = row[Columns.unlockHeight]
        try super.init(row: row)
    }
        
    override func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.tokenContract] = tokenContract
        container[Columns.addr] = addr
        container[Columns.amount] = amount
        container[Columns.lockDay] = lockDay
        container[Columns.startHeight] = startHeight
        container[Columns.unlockHeight] = unlockHeight
    }
    
    init(info: web3swift.LockRecord, tokenContract: String) {
        self.id = Int(info.id)
        self.tokenContract = tokenContract
        self.addr = info.addr.address
        self.amount = info.amount.description
        self.lockDay = Int(info.lockDay)
        self.startHeight = Int(info.startHeight)
        self.unlockHeight = Int(info.unlockHeight)
        super.init()
    }

    func transform() -> web3swift.LockRecord {
        return web3swift.LockRecord(id: BigUInt(id),
                                    addr: Web3Core.EthereumAddress(addr)!,
                                    amount: BigUInt(amount)!,
                                    lockDay: BigUInt(lockDay),
                                    startHeight: BigUInt(startHeight),
                                    unlockHeight: BigUInt(unlockHeight)
        )
    }
}

