import Foundation
import Testing
import XCTest
@testable import WalletCore

struct ManageWalletsTokenLoaderTests {
    @Test @MainActor func closingPageDuringQueryReleasesLoaderAndDropsCallback() async {
        let queue = DispatchQueue(label: "manage-wallets.token-loader-lifetime-test")
        var loader: ManageWalletsTokenLoader<String>? = ManageWalletsTokenLoader(queue: queue)
        weak var weakLoader = loader
        let started = XCTestExpectation(description: "Query started before dismissal")
        let drained = XCTestExpectation(description: "Pending callbacks drained")
        let releaseQuery = DispatchSemaphore(value: 0)
        var published = false

        loader?.load(work: {
            started.fulfill()
            #expect(releaseQuery.wait(timeout: .now() + 5) == .success)
            return "WSAFE"
        }, completion: { _ in published = true })

        let startResult = await XCTWaiter.fulfillment(of: [started], timeout: 5)
        #expect(startResult == .completed)
        loader = nil
        #expect(weakLoader == nil)
        releaseQuery.signal()
        queue.async {
            DispatchQueue.main.async { drained.fulfill() }
        }

        let result = await XCTWaiter.fulfillment(of: [drained], timeout: 5)
        #expect(result == .completed)
        #expect(!published)
    }

    @Test @MainActor func queriesRunOffMainAndPublishOnMain() async {
        let loader = ManageWalletsTokenLoader<String>()
        defer { withExtendedLifetime(loader) {} }
        let published = XCTestExpectation(description: "Result published")

        loader.load(work: {
            #expect(!Thread.isMainThread)
            return "WSAFE"
        }, completion: { value in
            #expect(Thread.isMainThread)
            #expect(value == "WSAFE")
            published.fulfill()
        })

        let result = await XCTWaiter.fulfillment(of: [published], timeout: 5)
        #expect(result == .completed)
    }

    @Test @MainActor func latestRequestReplacesRunningAndQueuedRequests() async {
        let loader = ManageWalletsTokenLoader<String>()
        defer { withExtendedLifetime(loader) {} }
        let started = XCTestExpectation(description: "Old query started")
        let published = XCTestExpectation(description: "Latest query published")
        let releaseOldQuery = DispatchSemaphore(value: 0)
        var results = [String]()

        loader.load(work: {
            started.fulfill()
            #expect(releaseOldQuery.wait(timeout: .now() + 5) == .success)
            return "old search"
        }, completion: { results.append($0) })

        let startResult = await XCTWaiter.fulfillment(of: [started], timeout: 5)
        #expect(startResult == .completed)

        loader.load(work: {
            Issue.record("Superseded queued query must not execute")
            return "superseded wallet state"
        }, completion: { results.append($0) })
        loader.load(work: { "latest wallet state" }, completion: {
            results.append($0)
            published.fulfill()
        })
        releaseOldQuery.signal()

        let result = await XCTWaiter.fulfillment(of: [published], timeout: 5)
        #expect(result == .completed)
        #expect(results == ["latest wallet state"])
    }

    @Test @MainActor func invalidationRejectsResultsDuringSearchDebounce() async {
        let queue = DispatchQueue(label: "manage-wallets.token-loader-test")
        let loader = ManageWalletsTokenLoader<String>(queue: queue)
        defer { withExtendedLifetime(loader) {} }
        let started = XCTestExpectation(description: "Query started")
        let drained = XCTestExpectation(description: "Query and its callback drained")
        let releaseQuery = DispatchSemaphore(value: 0)
        var results = [String]()

        loader.load(work: {
            started.fulfill()
            #expect(releaseQuery.wait(timeout: .now() + 5) == .success)
            return "stale search"
        }, completion: { results.append($0) })

        let startResult = await XCTWaiter.fulfillment(of: [started], timeout: 5)
        #expect(startResult == .completed)
        // Typing invalidates now, before the debounced replacement is scheduled.
        loader.invalidate()
        releaseQuery.signal()
        queue.async {
            DispatchQueue.main.async { drained.fulfill() }
        }

        let result = await XCTWaiter.fulfillment(of: [drained], timeout: 5)
        #expect(result == .completed)
        #expect(results.isEmpty)
    }
}
