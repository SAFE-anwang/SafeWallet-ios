import Foundation
import GRDB

protocol ChildWalletStore: AnyObject {
    func allChildWallets(parentAccountId: String) throws -> [ChildWallet]
    func childWallets(parentAccountId: String) throws -> [ChildWallet]
    func activeChildWallet(parentAccountId: String) throws -> ChildWallet?
    func save(childWallet: ChildWallet) throws
    func save(childWallets: [ChildWallet]) throws
    func setActiveChildWallet(parentAccountId: String, childWalletId: String?) throws
    func enabledWallets(childWalletId: String, parentAccountId: String) throws -> [EnabledWallet]
    func save(enabledWallets: [EnabledWallet], childWalletId: String, parentAccountId: String) throws
    func insert(enabledWallets: [ChildEnabledWallet], parentAccountId: String) throws
    func deleteAutoSeededEnabledWallets(tokenQueryIds: Set<String>, parentAccountId: String) throws
    func delete(tokenQueryIds: [String], childWalletId: String, parentAccountId: String) throws
    func parentState(parentAccountId: String) throws -> ChildWalletParentState?
    func save(parentState: ChildWalletParentState) throws
    func delete(parentAccountId: String) throws
}

func canonicalChildWallets(_ childWallets: [ChildWallet], parentAccountId: String, includeHidden: Bool) -> [ChildWallet] {
    var firstByIndex = [Int: ChildWallet]()
    for childWallet in childWallets
        .filter({ $0.parentAccountId == parentAccountId && (includeHidden || !$0.isHidden) })
        .sorted(by: { $0.createdAt < $1.createdAt })
    {
        if firstByIndex[childWallet.derivationIndex] == nil {
            firstByIndex[childWallet.derivationIndex] = childWallet
        }
    }

    return firstByIndex.values.sorted { $0.derivationIndex < $1.derivationIndex }
}

final class ChildWalletFileStorage: ChildWalletStore {
    fileprivate struct State: Codable {
        var childWallets = [ChildWallet]()
        var activeChildWalletIds = [String: String]()
        var enabledWallets = [ChildEnabledWallet]()
        var parentStates = [String: ChildWalletParentState]()

        private enum CodingKeys: String, CodingKey {
            case childWallets
            case activeChildWalletIds
            case enabledWallets
            case parentStates
        }

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            childWallets = try container.decodeIfPresent([ChildWallet].self, forKey: .childWallets) ?? []
            activeChildWalletIds = try container.decodeIfPresent([String: String].self, forKey: .activeChildWalletIds) ?? [:]
            enabledWallets = try container.decodeIfPresent([ChildEnabledWallet].self, forKey: .enabledWallets) ?? []
            parentStates = try container.decodeIfPresent([String: ChildWalletParentState].self, forKey: .parentStates) ?? [:]
        }
    }

    private let url: URL
    private let lock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(url: URL) {
        self.url = url
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    static func defaultStorage() -> ChildWalletStore {
        do {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("SafeWallet", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let jsonStorage = ChildWalletFileStorage(url: directory.appendingPathComponent("child_wallets.json"))
            do {
                return try ChildWalletGRDBStorage(url: directory.appendingPathComponent("child_wallets.sqlite"), legacyFileStorage: jsonStorage)
            } catch {
                return ChildWalletUnavailableStorage(reason: "Unable to open child wallet SQLite storage: \(error.localizedDescription)")
            }
        } catch {
            return ChildWalletUnavailableStorage(reason: "Unable to prepare child wallet storage directory: \(error.localizedDescription)")
        }
    }

    func allChildWallets(parentAccountId: String) throws -> [ChildWallet] {
        canonicalChildWallets(try read().childWallets, parentAccountId: parentAccountId, includeHidden: true)
    }

    func childWallets(parentAccountId: String) throws -> [ChildWallet] {
        canonicalChildWallets(try read().childWallets, parentAccountId: parentAccountId, includeHidden: false)
    }

    func activeChildWallet(parentAccountId: String) throws -> ChildWallet? {
        let state = try read()
        guard let id = state.activeChildWalletIds[parentAccountId] else {
            return nil
        }
        guard let active = state.childWallets.first(where: { $0.id == id && $0.parentAccountId == parentAccountId && !$0.isHidden }) else {
            return nil
        }

        return canonicalChildWallets(state.childWallets, parentAccountId: parentAccountId, includeHidden: false)
            .first { $0.derivationIndex == active.derivationIndex }
    }

    func save(childWallet: ChildWallet) throws {
        try save(childWallets: [childWallet])
    }

    func save(childWallets: [ChildWallet]) throws {
        try update { state in
            var indexesByParent = [String: [Int: String]]()
            for existing in state.childWallets {
                indexesByParent[existing.parentAccountId, default: [:]][existing.derivationIndex] = existing.id
            }

            for childWallet in childWallets {
                if let existingId = indexesByParent[childWallet.parentAccountId]?[childWallet.derivationIndex],
                   existingId != childWallet.id
                {
                    throw ChildWalletError.duplicateDerivationIndex
                }
                indexesByParent[childWallet.parentAccountId, default: [:]][childWallet.derivationIndex] = childWallet.id
            }

            for childWallet in childWallets {
                if let index = state.childWallets.firstIndex(where: { $0.id == childWallet.id }) {
                    state.childWallets[index] = childWallet
                } else {
                    state.childWallets.append(childWallet)
                }
            }
        }
    }

    func setActiveChildWallet(parentAccountId: String, childWalletId: String?) throws {
        try update { state in
            if let childWalletId {
                guard state.childWallets.contains(where: { $0.id == childWalletId && $0.parentAccountId == parentAccountId && !$0.isHidden }) else {
                    throw ChildWalletError.childWalletNotFound
                }
                state.activeChildWalletIds[parentAccountId] = childWalletId
            } else {
                state.activeChildWalletIds.removeValue(forKey: parentAccountId)
            }
        }
    }

    func enabledWallets(childWalletId: String, parentAccountId: String) throws -> [EnabledWallet] {
        let state = try read()
        guard state.childWallets.contains(where: { $0.id == childWalletId && $0.parentAccountId == parentAccountId && !$0.isHidden }) else {
            return []
        }

        return state.enabledWallets
            .filter { $0.childWalletId == childWalletId && ($0.parentAccountId == nil || $0.parentAccountId == parentAccountId) }
            .map { $0.enabledWallet(accountId: parentAccountId) }
    }

    func save(enabledWallets: [EnabledWallet], childWalletId: String, parentAccountId: String) throws {
        try update { state in
            guard state.childWallets.contains(where: { $0.id == childWalletId && $0.parentAccountId == parentAccountId && !$0.isHidden }) else {
                throw ChildWalletError.childWalletNotFound
            }

            let replacementIds = Set(enabledWallets.map { $0.tokenQueryId.lowercased() })
            state.enabledWallets.removeAll {
                $0.childWalletId == childWalletId
                    && ($0.parentAccountId == nil || $0.parentAccountId == parentAccountId)
                    && replacementIds.contains($0.tokenQueryId.lowercased())
            }
            state.enabledWallets.append(contentsOf: enabledWallets.map {
                ChildEnabledWallet(parentAccountId: parentAccountId, childWalletId: childWalletId, enabledWallet: $0)
            })
        }
    }

    func insert(enabledWallets: [ChildEnabledWallet], parentAccountId: String) throws {
        guard !enabledWallets.isEmpty else {
            return
        }

        try update { state in
            let visibleChildWalletIds = Set(state.childWallets.filter { $0.parentAccountId == parentAccountId && !$0.isHidden }.map(\.id))
            guard enabledWallets.allSatisfy({ visibleChildWalletIds.contains($0.childWalletId) && ($0.parentAccountId == nil || $0.parentAccountId == parentAccountId) }) else {
                throw ChildWalletError.childWalletNotFound
            }

            var existingKeys = Set(state.enabledWallets.map {
                [
                    $0.parentAccountId ?? parentAccountId,
                    $0.childWalletId,
                    $0.tokenQueryId.lowercased(),
                ].joined(separator: ":")
            })

            for enabledWallet in enabledWallets {
                let normalized = ChildEnabledWallet(
                    parentAccountId: parentAccountId,
                    childWalletId: enabledWallet.childWalletId,
                    tokenQueryId: enabledWallet.tokenQueryId,
                    coinName: enabledWallet.coinName,
                    coinCode: enabledWallet.coinCode,
                    coinImage: enabledWallet.coinImage,
                    tokenDecimals: enabledWallet.tokenDecimals
                )
                let key = [parentAccountId, normalized.childWalletId, normalized.tokenQueryId.lowercased()].joined(separator: ":")
                guard !existingKeys.contains(key) else {
                    continue
                }

                state.enabledWallets.append(normalized)
                existingKeys.insert(key)
            }
        }
    }

    func delete(tokenQueryIds: [String], childWalletId: String, parentAccountId: String) throws {
        try update { state in
            guard state.childWallets.contains(where: { $0.id == childWalletId && $0.parentAccountId == parentAccountId && !$0.isHidden }) else {
                throw ChildWalletError.childWalletNotFound
            }

            let deletedIds = Set(tokenQueryIds.map { $0.lowercased() })
            state.enabledWallets.removeAll {
                $0.childWalletId == childWalletId
                    && ($0.parentAccountId == nil || $0.parentAccountId == parentAccountId)
                    && deletedIds.contains($0.tokenQueryId.lowercased())
            }
        }
    }

    func deleteAutoSeededEnabledWallets(tokenQueryIds: Set<String>, parentAccountId: String) throws {
        let deletedIds = Set(tokenQueryIds.map { $0.lowercased() })

        try update { state in
            let visibleChildWalletIds = Set(state.childWallets.filter { $0.parentAccountId == parentAccountId && !$0.isHidden }.map(\.id))

            state.enabledWallets.removeAll {
                visibleChildWalletIds.contains($0.childWalletId)
                    && ($0.parentAccountId == nil || $0.parentAccountId == parentAccountId)
                    && deletedIds.contains($0.tokenQueryId.lowercased())
                    && $0.coinName == nil
                    && $0.coinCode == nil
                    && $0.coinImage == nil
                    && $0.tokenDecimals == nil
            }
        }
    }

    func parentState(parentAccountId: String) throws -> ChildWalletParentState? {
        try read().parentStates[parentAccountId]
    }

    func save(parentState: ChildWalletParentState) throws {
        try update { state in
            state.parentStates[parentState.parentAccountId] = parentState
        }
    }

    func delete(parentAccountId: String) throws {
        try update { state in
            let childWalletIds = Set(state.childWallets.filter { $0.parentAccountId == parentAccountId }.map(\.id))
            state.childWallets.removeAll { $0.parentAccountId == parentAccountId }
            state.activeChildWalletIds.removeValue(forKey: parentAccountId)
            state.enabledWallets.removeAll { childWalletIds.contains($0.childWalletId) || $0.parentAccountId == parentAccountId }
            state.parentStates.removeValue(forKey: parentAccountId)
        }
    }

    fileprivate func stateSnapshot() throws -> State {
        try read()
    }

    private func read() throws -> State {
        lock.lock()
        defer { lock.unlock() }

        guard FileManager.default.fileExists(atPath: url.path) else {
            return State()
        }

        let data = try Data(contentsOf: url)
        return try decoder.decode(State.self, from: data)
    }

    private func update(_ block: (inout State) throws -> Void) throws {
        lock.lock()
        defer { lock.unlock() }

        let state: State
        if FileManager.default.fileExists(atPath: url.path) {
            state = try decoder.decode(State.self, from: try Data(contentsOf: url))
        } else {
            state = State()
        }

        var updatedState = state
        try block(&updatedState)

        let data = try encoder.encode(updatedState)
        try data.write(to: url, options: .atomic)
    }
}

final class ChildWalletGRDBStorage: ChildWalletStore {
    private enum Tables {
        static let childWallets = "child_wallets"
        static let enabledWallets = "child_enabled_wallets"
        static let parentStates = "child_wallet_parent_states"
        static let activeChildWallets = "child_wallet_active_ids"
    }

    private enum Columns {
        static let id = "id"
        static let parentAccountId = "parentAccountId"
        static let derivationIndex = "derivationIndex"
        static let name = "name"
        static let isHidden = "isHidden"
        static let createdAt = "createdAt"
        static let creationSource = "creationSource"
        static let childWalletId = "childWalletId"
        static let tokenQueryId = "tokenQueryId"
        static let coinName = "coinName"
        static let coinCode = "coinCode"
        static let coinImage = "coinImage"
        static let tokenDecimals = "tokenDecimals"
        static let highestAllocatedIndex = "highestAllocatedIndex"
        static let legacyHighestDetectedIndex = "legacyHighestDetectedIndex"
        static let legacyAutoSeededEnabledWalletsCleaned = "legacyAutoSeededEnabledWalletsCleaned"
        static let updatedAt = "updatedAt"
    }

    private let dbPool: DatabasePool
    private let legacyFileStorage: ChildWalletFileStorage?

    init(url: URL, legacyFileStorage: ChildWalletFileStorage? = nil) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        dbPool = try DatabasePool(path: url.path)
        self.legacyFileStorage = legacyFileStorage

        try migrator.migrate(dbPool)
        try migrateLegacyJsonIfNeeded()
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("create child wallet tables") { db in
            try db.create(table: Tables.childWallets) { t in
                t.column(Columns.id, .text).notNull().primaryKey()
                t.column(Columns.parentAccountId, .text).notNull()
                t.column(Columns.derivationIndex, .integer).notNull()
                t.column(Columns.name, .text).notNull()
                t.column(Columns.isHidden, .boolean).notNull().defaults(to: false)
                t.column(Columns.createdAt, .double).notNull()
                t.column(Columns.creationSource, .text)
                t.uniqueKey([Columns.parentAccountId, Columns.derivationIndex])
            }
            try db.create(index: "idx_child_wallets_parent", on: Tables.childWallets, columns: [Columns.parentAccountId])

            try db.create(table: Tables.enabledWallets) { t in
                t.column(Columns.parentAccountId, .text).notNull()
                t.column(Columns.childWalletId, .text).notNull()
                t.column(Columns.tokenQueryId, .text).notNull()
                t.column(Columns.coinName, .text)
                t.column(Columns.coinCode, .text)
                t.column(Columns.coinImage, .text)
                t.column(Columns.tokenDecimals, .integer)
                t.primaryKey([Columns.parentAccountId, Columns.childWalletId, Columns.tokenQueryId])
            }
            try db.create(index: "idx_child_enabled_wallets_child", on: Tables.enabledWallets, columns: [Columns.parentAccountId, Columns.childWalletId])

            try db.create(table: Tables.parentStates) { t in
                t.column(Columns.parentAccountId, .text).notNull().primaryKey()
                t.column(Columns.highestAllocatedIndex, .integer).notNull()
                t.column(Columns.legacyHighestDetectedIndex, .integer).notNull()
                t.column(Columns.legacyAutoSeededEnabledWalletsCleaned, .boolean).notNull().defaults(to: false)
                t.column(Columns.createdAt, .double).notNull()
                t.column(Columns.updatedAt, .double).notNull()
            }

            try db.create(table: Tables.activeChildWallets) { t in
                t.column(Columns.parentAccountId, .text).notNull().primaryKey()
                t.column(Columns.childWalletId, .text).notNull()
            }
        }

        migrator.registerMigration("add child wallet legacy auto-seeded cleanup flag") { db in
            let hasColumn = try db.columns(in: Tables.parentStates).contains {
                $0.name == Columns.legacyAutoSeededEnabledWalletsCleaned
            }
            guard !hasColumn else {
                return
            }

            try db.alter(table: Tables.parentStates) { t in
                t.add(column: Columns.legacyAutoSeededEnabledWalletsCleaned, .boolean).notNull().defaults(to: false)
            }
        }

        return migrator
    }

    func allChildWallets(parentAccountId: String) throws -> [ChildWallet] {
        try dbPool.read { db in
            try childWallets(parentAccountId: parentAccountId, includeHidden: true, db: db)
        }
    }

    func childWallets(parentAccountId: String) throws -> [ChildWallet] {
        try dbPool.read { db in
            try childWallets(parentAccountId: parentAccountId, includeHidden: false, db: db)
        }
    }

    func activeChildWallet(parentAccountId: String) throws -> ChildWallet? {
        try dbPool.read { db in
            guard let activeChildWalletId = try String.fetchOne(
                db,
                sql: "SELECT \(Columns.childWalletId) FROM \(Tables.activeChildWallets) WHERE \(Columns.parentAccountId) = ?",
                arguments: [parentAccountId]
            ) else {
                return nil
            }

            return try childWallet(id: activeChildWalletId, parentAccountId: parentAccountId, includeHidden: false, db: db)
        }
    }

    func save(childWallet: ChildWallet) throws {
        try save(childWallets: [childWallet])
    }

    func save(childWallets: [ChildWallet]) throws {
        try dbPool.write { db in
            for childWallet in childWallets {
                try validateUniqueDerivationIndex(childWallet: childWallet, db: db)
            }

            for childWallet in childWallets {
                try save(childWallet: childWallet, db: db)
            }
        }
    }

    func setActiveChildWallet(parentAccountId: String, childWalletId: String?) throws {
        try dbPool.write { db in
            if let childWalletId {
                guard try childWallet(id: childWalletId, parentAccountId: parentAccountId, includeHidden: false, db: db) != nil else {
                    throw ChildWalletError.childWalletNotFound
                }

                try db.execute(
                    sql: """
                    INSERT OR REPLACE INTO \(Tables.activeChildWallets) (\(Columns.parentAccountId), \(Columns.childWalletId))
                    VALUES (?, ?)
                    """,
                    arguments: [parentAccountId, childWalletId]
                )
            } else {
                try db.execute(
                    sql: "DELETE FROM \(Tables.activeChildWallets) WHERE \(Columns.parentAccountId) = ?",
                    arguments: [parentAccountId]
                )
            }
        }
    }

    func enabledWallets(childWalletId: String, parentAccountId: String) throws -> [EnabledWallet] {
        try dbPool.read { db in
            guard try childWallet(id: childWalletId, parentAccountId: parentAccountId, includeHidden: false, db: db) != nil else {
                return []
            }

            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT \(Columns.tokenQueryId), \(Columns.coinName), \(Columns.coinCode), \(Columns.coinImage), \(Columns.tokenDecimals)
                FROM \(Tables.enabledWallets)
                WHERE \(Columns.parentAccountId) = ? AND \(Columns.childWalletId) = ?
                ORDER BY \(Columns.tokenQueryId)
                """,
                arguments: [parentAccountId, childWalletId]
            )

            return rows.map {
                EnabledWallet(
                    tokenQueryId: $0[Columns.tokenQueryId],
                    accountId: parentAccountId,
                    coinName: $0[Columns.coinName],
                    coinCode: $0[Columns.coinCode],
                    coinImage: $0[Columns.coinImage],
                    tokenDecimals: $0[Columns.tokenDecimals]
                )
            }
        }
    }

    func save(enabledWallets: [EnabledWallet], childWalletId: String, parentAccountId: String) throws {
        try dbPool.write { db in
            guard try childWallet(id: childWalletId, parentAccountId: parentAccountId, includeHidden: false, db: db) != nil else {
                throw ChildWalletError.childWalletNotFound
            }

            for tokenQueryId in Set(enabledWallets.map { $0.tokenQueryId.lowercased() }) {
                try delete(tokenQueryId: tokenQueryId, childWalletId: childWalletId, parentAccountId: parentAccountId, db: db)
            }

            for enabledWallet in enabledWallets {
                try save(enabledWallet: ChildEnabledWallet(parentAccountId: parentAccountId, childWalletId: childWalletId, enabledWallet: enabledWallet), db: db)
            }
        }
    }

    func insert(enabledWallets: [ChildEnabledWallet], parentAccountId: String) throws {
        guard !enabledWallets.isEmpty else {
            return
        }

        try dbPool.write { db in
            let visibleChildWalletIds = try Set(childWallets(parentAccountId: parentAccountId, includeHidden: false, db: db).map(\.id))
            guard enabledWallets.allSatisfy({ visibleChildWalletIds.contains($0.childWalletId) && ($0.parentAccountId == nil || $0.parentAccountId == parentAccountId) }) else {
                throw ChildWalletError.childWalletNotFound
            }

            var existingKeys = try Set(Row.fetchAll(
                db,
                sql: """
                SELECT \(Columns.parentAccountId), \(Columns.childWalletId), \(Columns.tokenQueryId)
                FROM \(Tables.enabledWallets)
                WHERE \(Columns.parentAccountId) = ?
                """,
                arguments: [parentAccountId]
            ).map {
                [$0[Columns.parentAccountId] as String, $0[Columns.childWalletId] as String, ($0[Columns.tokenQueryId] as String).lowercased()]
                    .joined(separator: ":")
            })

            for enabledWallet in enabledWallets {
                let normalized = ChildEnabledWallet(
                    parentAccountId: parentAccountId,
                    childWalletId: enabledWallet.childWalletId,
                    tokenQueryId: enabledWallet.tokenQueryId,
                    coinName: enabledWallet.coinName,
                    coinCode: enabledWallet.coinCode,
                    coinImage: enabledWallet.coinImage,
                    tokenDecimals: enabledWallet.tokenDecimals
                )
                let key = [parentAccountId, normalized.childWalletId, normalized.tokenQueryId.lowercased()].joined(separator: ":")
                guard !existingKeys.contains(key) else {
                    continue
                }

                try save(enabledWallet: normalized, db: db)
                existingKeys.insert(key)
            }
        }
    }

    func delete(tokenQueryIds: [String], childWalletId: String, parentAccountId: String) throws {
        try dbPool.write { db in
            guard try childWallet(id: childWalletId, parentAccountId: parentAccountId, includeHidden: false, db: db) != nil else {
                throw ChildWalletError.childWalletNotFound
            }

            for tokenQueryId in Set(tokenQueryIds.map { $0.lowercased() }) {
                try delete(tokenQueryId: tokenQueryId, childWalletId: childWalletId, parentAccountId: parentAccountId, db: db)
            }
        }
    }

    func deleteAutoSeededEnabledWallets(tokenQueryIds: Set<String>, parentAccountId: String) throws {
        guard !tokenQueryIds.isEmpty else {
            return
        }

        try dbPool.write { db in
            let placeholders = Array(repeating: "?", count: tokenQueryIds.count).joined(separator: ", ")

            try db.execute(
                sql: """
                DELETE FROM \(Tables.enabledWallets)
                WHERE \(Columns.parentAccountId) = ?
                    AND \(Columns.childWalletId) IN (
                        SELECT \(Columns.id)
                        FROM \(Tables.childWallets)
                        WHERE \(Columns.parentAccountId) = ?
                            AND \(Columns.isHidden) = 0
                    )
                    AND lower(\(Columns.tokenQueryId)) IN (\(placeholders))
                    AND \(Columns.coinName) IS NULL
                    AND \(Columns.coinCode) IS NULL
                    AND \(Columns.coinImage) IS NULL
                    AND \(Columns.tokenDecimals) IS NULL
                """,
                arguments: StatementArguments([parentAccountId, parentAccountId] + tokenQueryIds.map { $0.lowercased() })
            )
        }
    }

    func parentState(parentAccountId: String) throws -> ChildWalletParentState? {
        try dbPool.read { db in
            try parentState(parentAccountId: parentAccountId, db: db)
        }
    }

    func save(parentState: ChildWalletParentState) throws {
        try dbPool.write { db in
            try save(parentState: parentState, db: db)
        }
    }

    func delete(parentAccountId: String) throws {
        try dbPool.write { db in
            try db.execute(
                sql: "DELETE FROM \(Tables.enabledWallets) WHERE \(Columns.parentAccountId) = ?",
                arguments: [parentAccountId]
            )
            try db.execute(
                sql: "DELETE FROM \(Tables.activeChildWallets) WHERE \(Columns.parentAccountId) = ?",
                arguments: [parentAccountId]
            )
            try db.execute(
                sql: "DELETE FROM \(Tables.parentStates) WHERE \(Columns.parentAccountId) = ?",
                arguments: [parentAccountId]
            )
            try db.execute(
                sql: "DELETE FROM \(Tables.childWallets) WHERE \(Columns.parentAccountId) = ?",
                arguments: [parentAccountId]
            )
        }
    }

    private func migrateLegacyJsonIfNeeded() throws {
        guard let legacyState = try? legacyFileStorage?.stateSnapshot() else {
            return
        }

        try dbPool.write { db in
            let existingRowsCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(Tables.childWallets)") ?? 0
            let existingParentStatesCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(Tables.parentStates)") ?? 0
            guard existingRowsCount == 0, existingParentStatesCount == 0 else {
                return
            }

            let parentAccountIds = Set(
                legacyState.childWallets.map(\.parentAccountId)
                    + legacyState.parentStates.keys
                    + legacyState.activeChildWalletIds.keys
            )
            var childWalletIdsByParent = [String: Set<String>]()
            var visibleChildWalletIdsByParent = [String: Set<String>]()
            var migratedChildWallets = [ChildWallet]()

            for parentAccountId in parentAccountIds {
                let canonical = canonicalChildWallets(legacyState.childWallets, parentAccountId: parentAccountId, includeHidden: true)
                childWalletIdsByParent[parentAccountId] = Set(canonical.map(\.id))
                visibleChildWalletIdsByParent[parentAccountId] = Set(canonical.filter { !$0.isHidden }.map(\.id))
                migratedChildWallets.append(contentsOf: canonical)
            }

            for childWallet in migratedChildWallets {
                try save(childWallet: childWallet, db: db)
            }

            for childEnabledWallet in legacyState.enabledWallets {
                let resolvedParentAccountId = childEnabledWallet.parentAccountId
                    ?? migratedChildWallets.first(where: { $0.id == childEnabledWallet.childWalletId })?.parentAccountId
                guard let parentAccountId = resolvedParentAccountId,
                      childWalletIdsByParent[parentAccountId]?.contains(childEnabledWallet.childWalletId) == true
                else {
                    continue
                }

                try save(
                    enabledWallet: ChildEnabledWallet(
                        parentAccountId: parentAccountId,
                        childWalletId: childEnabledWallet.childWalletId,
                        tokenQueryId: childEnabledWallet.tokenQueryId,
                        coinName: childEnabledWallet.coinName,
                        coinCode: childEnabledWallet.coinCode,
                        coinImage: childEnabledWallet.coinImage,
                        tokenDecimals: childEnabledWallet.tokenDecimals
                    ),
                    db: db
                )
            }

            for parentState in legacyState.parentStates.values {
                try save(parentState: parentState, db: db)
            }

            for (parentAccountId, childWalletId) in legacyState.activeChildWalletIds {
                guard visibleChildWalletIdsByParent[parentAccountId]?.contains(childWalletId) == true else {
                    continue
                }

                try db.execute(
                    sql: """
                    INSERT OR REPLACE INTO \(Tables.activeChildWallets) (\(Columns.parentAccountId), \(Columns.childWalletId))
                    VALUES (?, ?)
                    """,
                    arguments: [parentAccountId, childWalletId]
                )
            }
        }
    }

    private func childWallets(parentAccountId: String, includeHidden: Bool, db: Database) throws -> [ChildWallet] {
        let hiddenPredicate = includeHidden ? "" : "AND \(Columns.isHidden) = 0"
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT \(Columns.id), \(Columns.parentAccountId), \(Columns.derivationIndex), \(Columns.name), \(Columns.isHidden), \(Columns.createdAt), \(Columns.creationSource)
            FROM \(Tables.childWallets)
            WHERE \(Columns.parentAccountId) = ? \(hiddenPredicate)
            ORDER BY \(Columns.derivationIndex), \(Columns.createdAt)
            """,
            arguments: [parentAccountId]
        )

        return try rows.map(decodeChildWallet(row:))
    }

    private func childWallet(id: String, parentAccountId: String, includeHidden: Bool, db: Database) throws -> ChildWallet? {
        let hiddenPredicate = includeHidden ? "" : "AND \(Columns.isHidden) = 0"
        guard let row = try Row.fetchOne(
            db,
            sql: """
            SELECT \(Columns.id), \(Columns.parentAccountId), \(Columns.derivationIndex), \(Columns.name), \(Columns.isHidden), \(Columns.createdAt), \(Columns.creationSource)
            FROM \(Tables.childWallets)
            WHERE \(Columns.id) = ? AND \(Columns.parentAccountId) = ? \(hiddenPredicate)
            """,
            arguments: [id, parentAccountId]
        ) else {
            return nil
        }

        return try decodeChildWallet(row: row)
    }

    private func decodeChildWallet(row: Row) throws -> ChildWallet {
        let creationSourceRawValue: String? = row[Columns.creationSource]
        return try ChildWallet(
            id: row[Columns.id],
            parentAccountId: row[Columns.parentAccountId],
            derivationIndex: row[Columns.derivationIndex],
            name: row[Columns.name],
            isHidden: row[Columns.isHidden],
            createdAt: row[Columns.createdAt],
            creationSource: creationSourceRawValue == nil ? nil : .userCreated
        )
    }

    private func validateUniqueDerivationIndex(childWallet: ChildWallet, db: Database) throws {
        let existingId = try String.fetchOne(
            db,
            sql: """
            SELECT \(Columns.id)
            FROM \(Tables.childWallets)
            WHERE \(Columns.parentAccountId) = ? AND \(Columns.derivationIndex) = ?
            """,
            arguments: [childWallet.parentAccountId, childWallet.derivationIndex]
        )

        if let existingId, existingId != childWallet.id {
            throw ChildWalletError.duplicateDerivationIndex
        }
    }

    private func save(childWallet: ChildWallet, db: Database) throws {
        try db.execute(
            sql: """
            INSERT OR REPLACE INTO \(Tables.childWallets)
                (\(Columns.id), \(Columns.parentAccountId), \(Columns.derivationIndex), \(Columns.name), \(Columns.isHidden), \(Columns.createdAt), \(Columns.creationSource))
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                childWallet.id,
                childWallet.parentAccountId,
                childWallet.derivationIndex,
                childWallet.name,
                childWallet.isHidden,
                childWallet.createdAt,
                childWallet.creationSource == nil ? nil : "userCreated",
            ]
        )
    }

    private func save(enabledWallet: ChildEnabledWallet, db: Database) throws {
        try db.execute(
            sql: """
            INSERT OR REPLACE INTO \(Tables.enabledWallets)
                (\(Columns.parentAccountId), \(Columns.childWalletId), \(Columns.tokenQueryId), \(Columns.coinName), \(Columns.coinCode), \(Columns.coinImage), \(Columns.tokenDecimals))
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                enabledWallet.parentAccountId,
                enabledWallet.childWalletId,
                enabledWallet.tokenQueryId,
                enabledWallet.coinName,
                enabledWallet.coinCode,
                enabledWallet.coinImage,
                enabledWallet.tokenDecimals,
            ]
        )
    }

    private func delete(tokenQueryId: String, childWalletId: String, parentAccountId: String, db: Database) throws {
        try db.execute(
            sql: """
            DELETE FROM \(Tables.enabledWallets)
            WHERE \(Columns.parentAccountId) = ?
                AND \(Columns.childWalletId) = ?
                AND lower(\(Columns.tokenQueryId)) = ?
            """,
            arguments: [parentAccountId, childWalletId, tokenQueryId]
        )
    }

    private func parentState(parentAccountId: String, db: Database) throws -> ChildWalletParentState? {
        guard let row = try Row.fetchOne(
            db,
            sql: """
                SELECT \(Columns.parentAccountId), \(Columns.highestAllocatedIndex), \(Columns.legacyHighestDetectedIndex), \(Columns.legacyAutoSeededEnabledWalletsCleaned), \(Columns.createdAt), \(Columns.updatedAt)
                FROM \(Tables.parentStates)
                WHERE \(Columns.parentAccountId) = ?
                """,
            arguments: [parentAccountId]
        ) else {
            return nil
        }

        return ChildWalletParentState(
            parentAccountId: row[Columns.parentAccountId],
            highestAllocatedIndex: row[Columns.highestAllocatedIndex],
            legacyHighestDetectedIndex: row[Columns.legacyHighestDetectedIndex],
            legacyAutoSeededEnabledWalletsCleaned: row[Columns.legacyAutoSeededEnabledWalletsCleaned],
            createdAt: row[Columns.createdAt],
            updatedAt: row[Columns.updatedAt]
        )
    }

    private func save(parentState: ChildWalletParentState, db: Database) throws {
        try db.execute(
            sql: """
            INSERT OR REPLACE INTO \(Tables.parentStates)
                (\(Columns.parentAccountId), \(Columns.highestAllocatedIndex), \(Columns.legacyHighestDetectedIndex), \(Columns.legacyAutoSeededEnabledWalletsCleaned), \(Columns.createdAt), \(Columns.updatedAt))
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                parentState.parentAccountId,
                parentState.highestAllocatedIndex,
                parentState.legacyHighestDetectedIndex,
                parentState.legacyAutoSeededEnabledWalletsCleaned,
                parentState.createdAt,
                parentState.updatedAt,
            ]
        )
    }
}

private final class ChildWalletMemoryStorage: ChildWalletStore {
    private var state = ChildWalletFileStorage.State()
    private let lock = NSLock()

    func allChildWallets(parentAccountId: String) throws -> [ChildWallet] {
        lock.lock()
        defer { lock.unlock() }
        return canonicalChildWallets(state.childWallets, parentAccountId: parentAccountId, includeHidden: true)
    }

    func childWallets(parentAccountId: String) throws -> [ChildWallet] {
        lock.lock()
        defer { lock.unlock() }
        return canonicalChildWallets(state.childWallets, parentAccountId: parentAccountId, includeHidden: false)
    }

    func activeChildWallet(parentAccountId: String) throws -> ChildWallet? {
        lock.lock()
        defer { lock.unlock() }
        guard let id = state.activeChildWalletIds[parentAccountId] else {
            return nil
        }
        guard let active = state.childWallets.first(where: { $0.id == id && $0.parentAccountId == parentAccountId && !$0.isHidden }) else {
            return nil
        }

        return canonicalChildWallets(state.childWallets, parentAccountId: parentAccountId, includeHidden: false)
            .first { $0.derivationIndex == active.derivationIndex }
    }

    func save(childWallet: ChildWallet) throws {
        lock.lock()
        defer { lock.unlock() }

        try saveLocked(childWallets: [childWallet])
    }

    func save(childWallets: [ChildWallet]) throws {
        lock.lock()
        defer { lock.unlock() }

        try saveLocked(childWallets: childWallets)
    }

    func setActiveChildWallet(parentAccountId: String, childWalletId: String?) throws {
        lock.lock()
        defer { lock.unlock() }

        if let childWalletId {
            guard state.childWallets.contains(where: { $0.id == childWalletId && $0.parentAccountId == parentAccountId && !$0.isHidden }) else {
                throw ChildWalletError.childWalletNotFound
            }
            state.activeChildWalletIds[parentAccountId] = childWalletId
        } else {
            state.activeChildWalletIds.removeValue(forKey: parentAccountId)
        }
    }

    func enabledWallets(childWalletId: String, parentAccountId: String) throws -> [EnabledWallet] {
        lock.lock()
        defer { lock.unlock() }

        guard state.childWallets.contains(where: { $0.id == childWalletId && $0.parentAccountId == parentAccountId && !$0.isHidden }) else {
            return []
        }

        return state.enabledWallets
            .filter { $0.childWalletId == childWalletId && ($0.parentAccountId == nil || $0.parentAccountId == parentAccountId) }
            .map { $0.enabledWallet(accountId: parentAccountId) }
    }

    func save(enabledWallets: [EnabledWallet], childWalletId: String, parentAccountId: String) throws {
        lock.lock()
        defer { lock.unlock() }

        guard state.childWallets.contains(where: { $0.id == childWalletId && $0.parentAccountId == parentAccountId && !$0.isHidden }) else {
            throw ChildWalletError.childWalletNotFound
        }

        let replacementIds = Set(enabledWallets.map { $0.tokenQueryId.lowercased() })
        state.enabledWallets.removeAll {
            $0.childWalletId == childWalletId
                && ($0.parentAccountId == nil || $0.parentAccountId == parentAccountId)
                && replacementIds.contains($0.tokenQueryId.lowercased())
        }
        state.enabledWallets.append(contentsOf: enabledWallets.map {
            ChildEnabledWallet(parentAccountId: parentAccountId, childWalletId: childWalletId, enabledWallet: $0)
        })
    }

    func insert(enabledWallets: [ChildEnabledWallet], parentAccountId: String) throws {
        lock.lock()
        defer { lock.unlock() }

        let visibleChildWalletIds = Set(state.childWallets.filter { $0.parentAccountId == parentAccountId && !$0.isHidden }.map(\.id))
        guard enabledWallets.allSatisfy({ visibleChildWalletIds.contains($0.childWalletId) && ($0.parentAccountId == nil || $0.parentAccountId == parentAccountId) }) else {
            throw ChildWalletError.childWalletNotFound
        }

        var existingKeys = Set(state.enabledWallets.map {
            [
                $0.parentAccountId ?? parentAccountId,
                $0.childWalletId,
                $0.tokenQueryId.lowercased(),
            ].joined(separator: ":")
        })

        for enabledWallet in enabledWallets {
            let normalized = ChildEnabledWallet(
                parentAccountId: parentAccountId,
                childWalletId: enabledWallet.childWalletId,
                tokenQueryId: enabledWallet.tokenQueryId,
                coinName: enabledWallet.coinName,
                coinCode: enabledWallet.coinCode,
                coinImage: enabledWallet.coinImage,
                tokenDecimals: enabledWallet.tokenDecimals
            )
            let key = [parentAccountId, normalized.childWalletId, normalized.tokenQueryId.lowercased()].joined(separator: ":")
            guard !existingKeys.contains(key) else {
                continue
            }

            state.enabledWallets.append(normalized)
            existingKeys.insert(key)
        }
    }

    func delete(tokenQueryIds: [String], childWalletId: String, parentAccountId: String) throws {
        lock.lock()
        defer { lock.unlock() }

        guard state.childWallets.contains(where: { $0.id == childWalletId && $0.parentAccountId == parentAccountId && !$0.isHidden }) else {
            throw ChildWalletError.childWalletNotFound
        }

        let deletedIds = Set(tokenQueryIds.map { $0.lowercased() })
        state.enabledWallets.removeAll {
            $0.childWalletId == childWalletId
                && ($0.parentAccountId == nil || $0.parentAccountId == parentAccountId)
                && deletedIds.contains($0.tokenQueryId.lowercased())
        }
    }

    func parentState(parentAccountId: String) throws -> ChildWalletParentState? {
        lock.lock()
        defer { lock.unlock() }
        return state.parentStates[parentAccountId]
    }

    func save(parentState: ChildWalletParentState) throws {
        lock.lock()
        defer { lock.unlock() }
        state.parentStates[parentState.parentAccountId] = parentState
    }

    func delete(parentAccountId: String) throws {
        lock.lock()
        defer { lock.unlock() }

        let childWalletIds = Set(state.childWallets.filter { $0.parentAccountId == parentAccountId }.map(\.id))
        state.childWallets.removeAll { $0.parentAccountId == parentAccountId }
        state.activeChildWalletIds.removeValue(forKey: parentAccountId)
        state.enabledWallets.removeAll { childWalletIds.contains($0.childWalletId) || $0.parentAccountId == parentAccountId }
        state.parentStates.removeValue(forKey: parentAccountId)
    }

    private func saveLocked(childWallets: [ChildWallet]) throws {
        var indexesByParent = [String: [Int: String]]()
        for existing in state.childWallets {
            indexesByParent[existing.parentAccountId, default: [:]][existing.derivationIndex] = existing.id
        }

        for childWallet in childWallets {
            if let existingId = indexesByParent[childWallet.parentAccountId]?[childWallet.derivationIndex],
               existingId != childWallet.id
            {
                throw ChildWalletError.duplicateDerivationIndex
            }
            indexesByParent[childWallet.parentAccountId, default: [:]][childWallet.derivationIndex] = childWallet.id
        }

        for childWallet in childWallets {
            if let index = state.childWallets.firstIndex(where: { $0.id == childWallet.id }) {
                state.childWallets[index] = childWallet
            } else {
                state.childWallets.append(childWallet)
            }
        }
    }

    func deleteAutoSeededEnabledWallets(tokenQueryIds: Set<String>, parentAccountId: String) throws {
        lock.lock()
        defer { lock.unlock() }

        let deletedIds = Set(tokenQueryIds.map { $0.lowercased() })
        let visibleChildWalletIds = Set(state.childWallets.filter { $0.parentAccountId == parentAccountId && !$0.isHidden }.map(\.id))
        state.enabledWallets.removeAll {
            visibleChildWalletIds.contains($0.childWalletId)
                && ($0.parentAccountId == nil || $0.parentAccountId == parentAccountId)
                && deletedIds.contains($0.tokenQueryId.lowercased())
                && $0.coinName == nil
                && $0.coinCode == nil
                && $0.coinImage == nil
                && $0.tokenDecimals == nil
        }
    }
}

private final class ChildWalletUnavailableStorage: ChildWalletStore {
    private let reason: String

    init(reason: String) {
        self.reason = reason
    }

    private func unavailable() -> ChildWalletError {
        .storageUnavailable(reason)
    }

    func allChildWallets(parentAccountId _: String) throws -> [ChildWallet] {
        throw unavailable()
    }

    func childWallets(parentAccountId _: String) throws -> [ChildWallet] {
        throw unavailable()
    }

    func activeChildWallet(parentAccountId _: String) throws -> ChildWallet? {
        throw unavailable()
    }

    func save(childWallet _: ChildWallet) throws {
        throw unavailable()
    }

    func save(childWallets _: [ChildWallet]) throws {
        throw unavailable()
    }

    func setActiveChildWallet(parentAccountId _: String, childWalletId _: String?) throws {
        throw unavailable()
    }

    func enabledWallets(childWalletId _: String, parentAccountId _: String) throws -> [EnabledWallet] {
        throw unavailable()
    }

    func save(enabledWallets _: [EnabledWallet], childWalletId _: String, parentAccountId _: String) throws {
        throw unavailable()
    }

    func insert(enabledWallets _: [ChildEnabledWallet], parentAccountId _: String) throws {
        throw unavailable()
    }

    func deleteAutoSeededEnabledWallets(tokenQueryIds _: Set<String>, parentAccountId _: String) throws {
        throw unavailable()
    }

    func delete(tokenQueryIds _: [String], childWalletId _: String, parentAccountId _: String) throws {
        throw unavailable()
    }

    func parentState(parentAccountId _: String) throws -> ChildWalletParentState? {
        throw unavailable()
    }

    func save(parentState _: ChildWalletParentState) throws {
        throw unavailable()
    }

    func delete(parentAccountId _: String) throws {
        throw unavailable()
    }
}
