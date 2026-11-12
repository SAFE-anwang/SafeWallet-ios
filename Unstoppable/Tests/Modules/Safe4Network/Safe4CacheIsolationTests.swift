import Foundation
import BigInt
import GRDB
import XCTest

@testable import WalletCore

final class Safe4CacheIsolationTests: XCTestCase {
    private let main = Safe4CacheScope(chainId: 6666665, owner: "0xabc")
    private let test = Safe4CacheScope(chainId: 6666666, owner: "0xabc")

    func testPreferencesAreSeparatedByNetworkOwnerAndPurpose() throws {
        let suite = "Safe4CacheIsolationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let otherOwner = Safe4CacheScope(chainId: main.chainId, owner: "0xdef")
        let names = ["withdraw_ids", "withdraw_page", "withdraw_timestamp", "proposal_page", "dapp_draft", "crosschain_config"]
        for name in names {
            defaults.set("main", forKey: main.key(name))
            defaults.set("test", forKey: test.key(name))
            XCTAssertEqual(defaults.string(forKey: main.key(name)), "main")
            XCTAssertEqual(defaults.string(forKey: test.key(name)), "test")
            XCTAssertNil(defaults.string(forKey: otherOwner.key(name)))
            defaults.removeObject(forKey: test.key(name))
            XCTAssertEqual(defaults.string(forKey: main.key(name)), "main")
        }
        XCTAssertEqual(main, Safe4CacheScope(chainId: main.chainId, owner: "0xABC"))
        XCTAssertEqual(Set(names.map(main.key)).count, names.count)
        let unsafeOwner = Safe4CacheScope(chainId: main.chainId, owner: "../wallet/name")
        XCTAssertFalse(unsafeOwner.databaseName.contains("/"))
        XCTAssertNotEqual(main.databaseName, test.databaseName)
    }

    func testRecordIDsAndClearAreIsolatedAcrossNetworksAndWallets() throws {
        try withStorage { storage, _ in
            let mainStorage = try storage.scoped(main).lockedRecoardStorage
            let testStorage = try storage.scoped(test).lockedRecoardStorage
            let other = try storage.scoped(Safe4CacheScope(chainId: main.chainId, owner: "0xdef")).lockedRecoardStorage
            try mainStorage.replaceAll(records: [record(amount: "100")])
            try testStorage.replaceAll(records: [record(amount: "200")])
            try other.replaceAll(records: [record(amount: "300")])
            XCTAssertEqual(try mainStorage.allRecords().first?.record.amount, "100")
            XCTAssertEqual(try testStorage.allRecords().first?.record.amount, "200")
            XCTAssertEqual(try other.allRecords().first?.record.amount, "300")
            try testStorage.clear()
            XCTAssertTrue(try testStorage.allRecords().isEmpty)
            XCTAssertEqual(try mainStorage.allRecords().first?.record.amount, "100")
            XCTAssertEqual(try other.allRecords().first?.record.amount, "300")
            // A late response retains its original scope after another network has loaded.
            try mainStorage.replaceAll(records: [record(amount: "400")])
            XCTAssertTrue(try testStorage.allRecords().isEmpty)
            XCTAssertEqual(try other.allRecords().first?.record.amount, "300")
        }
    }

    func testLegacyCacheIsIgnoredAndScopedCacheSurvivesReopen() throws {
        try withStorage { storage, path in
            try storage.lockedRecoardStorage.replaceAll(records: [record(amount: "999")])
            let scoped = try storage.scoped(main)
            XCTAssertTrue(try scoped.lockedRecoardStorage.allRecords().isEmpty)
            XCTAssertTrue(scoped === (try storage.scoped(Safe4CacheScope(chainId: main.chainId, owner: "0xABC"))))
            try scoped.lockedRecoardStorage.replaceAll(records: [record(amount: "100")])
            let reopened = try Safe4StorageManager(dbPool: DatabasePool(path: path))
            XCTAssertEqual(try reopened.scoped(main).lockedRecoardStorage.allRecords().first?.record.amount, "100")
            XCTAssertTrue(try reopened.scoped(test).lockedRecoardStorage.allRecords().isEmpty)
            XCTAssertEqual(try reopened.lockedRecoardStorage.allRecords().first?.record.amount, "999")
        }
    }

    func testTokenLockIDsAndDeletesAreIsolatedByContract() throws {
        try withStorage { storage, _ in
            let first = try storage.scoped(Safe4CacheScope(chainId: main.chainId, owner: "0xabc:0x111")).src20AllTokenLockedsRecordStorage
            let second = try storage.scoped(Safe4CacheScope(chainId: main.chainId, owner: "0xabc:0x222")).src20AllTokenLockedsRecordStorage
            first.save(recoard: Src20TokenLockedRecord(id: 1, tokenContract: "0x111", addr: "0xabc", amount: "100", lockDay: 1, startHeight: 1, unlockHeight: 2))
            second.save(recoard: Src20TokenLockedRecord(id: 1, tokenContract: "0x222", addr: "0xabc", amount: "200", lockDay: 1, startHeight: 1, unlockHeight: 2))
            XCTAssertEqual(try first.tokenRecords(tokenContract: "0x111").first?.amount, "100")
            XCTAssertEqual(try second.tokenRecords(tokenContract: "0x222").first?.amount, "200")
            second.delete(id: 1, addr: "0xabc")
            XCTAssertTrue(try second.tokenRecords(tokenContract: "0x222").isEmpty)
            XCTAssertEqual(try first.tokenRecords(tokenContract: "0x111").first?.amount, "100")
        }
    }

    private func record(amount: String) -> Safe4LockedRecord {
        Safe4LockedRecord(type: .locked, record: Safe4AccountRecord(
            type: 0, id: 1, address: "0x0000000000000000000000000000000000000001",
            amount: amount, lockDay: "1", startHeight: "1", unlockHeight: "2"
        ), info: nil)
    }

    func testTokenWritesRejectStaleNetworkBeforeRPC() async throws {
        let staleChain = Safe4Network.chainId(testNet: !Safe4Network.currentContext.isTestNet)
        let service = SRC20Service(privateKey: Data(), lockAddress: "", chainId: staleChain)
        do {
            _ = try await service.deploy(type: .SRC20, name: "test", symbol: "TST", totalSupply: 1)
            XCTFail("A stale service must not deploy a token")
        } catch Safe4NetworkError.staleContext(let expected, let current) {
            XCTAssertEqual(expected, staleChain)
            XCTAssertEqual(current, Safe4Network.currentChainId)
        }
        do {
            _ = try await service.burn(amount: 1)
            XCTFail("A stale service must not burn tokens")
        } catch Safe4NetworkError.staleContext(let expected, _) {
            XCTAssertEqual(expected, staleChain)
        }
    }

    private func withStorage(_ body: (Safe4StorageManager, String) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("wallet.sqlite").path
        let storage = try Safe4StorageManager(dbPool: DatabasePool(path: path))
        try body(storage, path)
    }
}
