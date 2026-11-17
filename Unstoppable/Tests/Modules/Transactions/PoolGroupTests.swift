import Foundation
import MarketKit
import RxSwift
import XCTest
@testable import WalletCore

final class PoolGroupTests: XCTestCase {
    func testManySynchronousPoolsCompleteOnWorkerThread() {
        let completed = expectation(description: "All synchronous pools complete")
        DispatchQueue(label: "pool-group.stack-regression").async {
            var reads = 0
            let pools = (0 ..< 512).map { _ in
                Pool(provider: StubProvider {
                    reads += 1
                    return .just([])
                })
            }
            let group = PoolGroup(pools: pools)
            let disposable = group.itemsSingle(count: 20).subscribe(onSuccess: { items in
                XCTAssertTrue(items.isEmpty)
                XCTAssertEqual(reads, 512)
                completed.fulfill()
            }, onError: { error in
                XCTFail("Unexpected error: \(error)")
                completed.fulfill()
            })
            withExtendedLifetime(group) { disposable.dispose() }
        }
        wait(for: [completed], timeout: 30)
    }

    func testReadsAreDeferredAndNextPoolWaitsForCompletion() {
        let first = PublishSubject<[TransactionRecord]>()
        var reads: [Int] = []
        let group = PoolGroup(pools: [
            Pool(provider: StubProvider { reads.append(1); return first.asSingle() }),
            Pool(provider: StubProvider { reads.append(2); return .just([]) }),
        ])
        let request = group.itemsSingle(count: 20)
        XCTAssertTrue(reads.isEmpty)
        var completed = false
        let disposable = request.subscribe(onSuccess: { _ in completed = true })
        defer { disposable.dispose() }

        XCTAssertEqual(reads, [1])
        first.onNext([])
        XCTAssertEqual(reads, [1])
        XCTAssertFalse(completed)
        first.onCompleted()
        XCTAssertEqual(reads, [1, 2])
        XCTAssertTrue(completed)
    }

    func testCancellationDoesNotReadRemainingPools() {
        let first = PublishSubject<[TransactionRecord]>()
        var laterReads = 0
        let group = PoolGroup(pools: [
            Pool(provider: StubProvider { first.asSingle() }),
            Pool(provider: StubProvider { laterReads += 1; return .just([]) }),
        ])
        let disposable = group.itemsSingle(count: 20).subscribe(onSuccess: { _ in
            XCTFail("Cancelled request must not publish results")
        })
        XCTAssertTrue(first.hasObservers)
        disposable.dispose()
        XCTAssertFalse(first.hasObservers)
        first.onNext([])
        first.onCompleted()
        XCTAssertEqual(laterReads, 0)
    }

    func testErrorStopsRemainingPoolsAndPropagates() {
        var laterReads = 0
        var receivedError: Error?
        let group = PoolGroup(pools: [
            Pool(provider: StubProvider { .error(TestError.failed) }),
            Pool(provider: StubProvider { laterReads += 1; return .just([]) }),
        ])
        let disposable = group.itemsSingle(count: 20).subscribe(onSuccess: { _ in
            XCTFail("Failed request must not publish results")
        }, onError: { receivedError = $0 })
        defer { disposable.dispose() }
        XCTAssertEqual(receivedError as? TestError, .failed)
        XCTAssertEqual(laterReads, 0)
    }

    func testResultsAreSortedAcrossPoolsAndLimited() {
        let older = record("older", timestamp: 10)
        let newest = record("newest", timestamp: 30)
        let middle = record("middle", timestamp: 20)
        let group = PoolGroup(pools: [
            Pool(provider: StubProvider { .just([older, newest]) }),
            Pool(provider: StubProvider { .just([middle]) }),
        ])
        var result: [String]?
        let disposable = group.itemsSingle(count: 2).subscribe(onSuccess: {
            result = $0.map { $0.record.uid }
        })
        defer { disposable.dispose() }
        XCTAssertEqual(result, ["newest", "middle"])
    }

    func testEmptyGroupReturnsEmptyResult() {
        let group = PoolGroup(pools: [])
        var result: [TransactionItem]?
        let disposable = group.itemsSingle(count: 20).subscribe(onSuccess: { result = $0 })
        defer { disposable.dispose() }
        XCTAssertEqual(result?.count, 0)
    }

    private func record(_ uid: String, timestamp: TimeInterval) -> TransactionRecord {
        TransactionRecord(
            source: TransactionSource(blockchainType: .ethereum, meta: nil),
            uid: uid, transactionHash: uid, transactionIndex: 0,
            blockHeight: nil, confirmationsThreshold: nil,
            date: Date(timeIntervalSince1970: timestamp), failed: false
        )
    }

    private enum TestError: Error { case failed }

    private final class StubProvider: IPoolProvider {
        let syncing = false
        let syncingObservable = Observable<Bool>.never()
        let lastBlockInfo: LastBlockInfo? = nil
        private let read: () -> Single<[TransactionRecord]>

        init(read: @escaping () -> Single<[TransactionRecord]>) {
            self.read = read
        }

        func recordsSingle(from: TransactionRecord?, limit: Int) -> Single<[TransactionRecord]> { read() }
        func recordsObservable() -> Observable<[TransactionRecord]> { .never() }
        func lastBlockUpdatedObservable() -> Observable<Void> { .never() }
    }
}
