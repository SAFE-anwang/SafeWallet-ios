import BigInt
import Combine
import Foundation
import GRDB
import XCTest
import web3swift
@testable import WalletCore

final class SRC20LockedServiceTests: XCTestCase {
    func testImmediateStartDuringRepeatedConstruction() async throws {
        let fixture = try makeService()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let pool = try DatabasePool(path: fixture.directory.appendingPathComponent("startup.sqlite").path)
        let storage = try Src20AllTokenLockedRecordStorage(dbPool: pool)
        var runs: [(SRC20LockedService, StubRPC)] = []
        for _ in 0..<128 {
            let rpc = StubRPC()
            let service = SRC20LockedService(service: rpc, lockedRecordStorage: storage)
            XCTAssertEqual(service.state, .syncing)
            service.start()
            runs.append((service, rpc))
        }
        for (service, rpc) in runs {
            await waitUntil { await rpc.gate.count > 0 }
            let count = await rpc.gate.count
            XCTAssertEqual(count, 1, "init followed by start must only schedule one run")
            await rpc.gate.finish()
            await waitUntil { service.state == .synced }
        }
        await waitUntil { await fixture.rpc.gate.count > 0 }
        await fixture.rpc.gate.finish()
        await waitUntil { fixture.service.state == .synced }
    }

    func testConcurrentStartsShareOneRunAndCanRefreshAfterCompletion() async throws {
        let fixture = try makeService()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let service = fixture.service
        XCTAssertEqual(service.state, .syncing)
        service.start() // Same immediate init/start sequence as Eip20Adapter.
        DispatchQueue.concurrentPerform(iterations: 256) { _ in
            service.start()
            XCTAssertEqual(service.state, .syncing)
        }
        await waitUntil { await fixture.rpc.gate.count == 1 }
        let count = await fixture.rpc.gate.count
        XCTAssertEqual(count, 1)
        let amount = expectation(description: "Zero locked balance is published")
        let subscription = service.lockedAmountPublisher.sink { value in
            XCTAssertEqual(value, .zero)
            amount.fulfill()
        }
        await fixture.rpc.gate.finish()
        await fulfillment(of: [amount], timeout: 5)
        subscription.cancel()
        await waitUntil { service.state == .synced }

        service.start()
        await waitUntil { await fixture.rpc.gate.count == 2 }
        await fixture.rpc.gate.finish()
        await waitUntil { service.state == .synced }
    }

    func testFailureAllowsRetryAndTokensDoNotWaitForEachOther() async throws {
        let first = try makeService()
        let second = try makeService()
        defer {
            try? FileManager.default.removeItem(at: first.directory)
            try? FileManager.default.removeItem(at: second.directory)
        }
        await waitUntil { await first.rpc.gate.count == 1 }
        await waitUntil { await second.rpc.gate.count == 1 }
        // Both requests reach the RPC before either one finishes.
        await first.rpc.gate.finish(error: TestError.failed)
        await waitUntil { first.service.state.isNotSynced }
        XCTAssertEqual(second.service.state, .syncing)
        first.service.start()
        await waitUntil { await first.rpc.gate.count == 2 }
        await first.rpc.gate.finish()
        await second.rpc.gate.finish()
        await waitUntil { first.service.state == .synced && second.service.state == .synced }
    }

    private func makeService() throws -> (service: SRC20LockedService, rpc: StubRPC, directory: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pool = try DatabasePool(path: directory.appendingPathComponent("locked.sqlite").path)
        let storage = try Src20AllTokenLockedRecordStorage(dbPool: pool)
        let rpc = StubRPC()
        return (SRC20LockedService(service: rpc, lockedRecordStorage: storage), rpc, directory)
    }

    private func waitUntil(_ predicate: () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<1000 {
            if await predicate() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Timed out waiting for sync transition", file: file, line: line)
    }

    private enum TestError: Error { case failed }

    private class StubRPC: SRC20LockedRecordProvider {
        let contract = "0x0000000000000000000000000000000000000001"
        let gate = Gate()
        func getLockedIDNum() async throws -> BigUInt {
            try await gate.request()
        }
        func getLockedIDs(start: BigUInt, count: BigUInt) async throws -> [BigUInt] {
            XCTFail("Zero locked records must not load IDs")
            return []
        }
        func getRecordByID(id: BigUInt) async throws -> LockRecord {
            XCTFail("Zero locked records must not load records")
            throw TestError.failed
        }
    }

    private actor Gate {
        private(set) var count = 0
        private var pending: [CheckedContinuation<BigUInt, Error>] = []
        func request() async throws -> BigUInt {
            count += 1
            return try await withCheckedThrowingContinuation { pending.append($0) }
        }
        func finish(error: Error? = nil) {
            let requests = pending
            pending.removeAll()
            for request in requests {
                if let error { request.resume(throwing: error) }
                else { request.resume(returning: .zero) }
            }
        }
    }
}
