import Combine
import Foundation
import GRDB
import Testing
import XCTest
@testable import WalletCore

struct Safe4TokenSyncStorageTests {
    private let chainId = 666
    private let owner = "0x1111111111111111111111111111111111111111"

    @Test @MainActor func catalogObservationDoesNotOpenSnapshotReader() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("safe4-writer-observation-\(UUID().uuidString).sqlite")
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            // DatabasePool snapshot observations open a read-only connection.
            // Reject that path so this test fails without the device workaround.
            if db.configuration.readonly {
                throw NSError(domain: "UnexpectedSnapshotReader", code: 1)
            }
        }
        let storage = try Safe4CustomTokenStorage(dbPool: DatabasePool(path: databaseURL.path, configuration: configuration))
        let initial = XCTestExpectation(description: "Initial observation uses writer")
        let updated = XCTestExpectation(description: "Committed update uses writer")
        var count = 0
        let subscription = storage.tokensUpdatedPublisher.sink {
            count += 1
            if count == 1 { initial.fulfill() }
            if count == 2 { updated.fulfill() }
        }
        defer { subscription.cancel() }
        let initialResult = await XCTWaiter.fulfillment(of: [initial], timeout: 5)
        #expect(initialResult == .completed)
        try storage.synchronize(
            tokens: [token("0x0000000000000000000000000000000000001101", creator: "")],
            ownedBy: owner, ownedAddresses: [], chainId: chainId
        )
        let updatedResult = await XCTWaiter.fulfillment(of: [updated], timeout: 5)
        #expect(updatedResult == .completed)
    }

    @Test @MainActor func catalogObserverSeesWrappedSafeInsertedAfterOpeningList() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("safe4-catalog-observation-\(UUID().uuidString).sqlite")
        let storage = try Safe4CustomTokenStorage(dbPool: DatabasePool(path: databaseURL.path))
        let initialSnapshot = XCTestExpectation(description: "Initial empty catalog")
        let updatedSnapshot = XCTestExpectation(description: "WSAFE appears without changing the search")
        let wrappedSafe = token("0x0000000000000000000000000000000000001101", creator: "")
        var snapshots = [[String]]()
        let subscription = storage.tokensUpdatedPublisher.sink {
            let addresses = storage.allTokens(chainId: chainId)
                .filter { $0.isEligible(forOwner: owner) }
                .map(\.address)
            snapshots.append(addresses)
            if snapshots.count == 1 {
                initialSnapshot.fulfill()
            } else if addresses.contains(wrappedSafe.address) {
                updatedSnapshot.fulfill()
            }
        }
        defer { subscription.cancel() }

        let initialResult = await XCTWaiter.fulfillment(of: [initialSnapshot], timeout: 5)
        #expect(initialResult == .completed)
        #expect(snapshots.first == [])

        try storage.synchronize(tokens: [wrappedSafe], ownedBy: owner, ownedAddresses: [], chainId: chainId)

        let updateResult = await XCTWaiter.fulfillment(of: [updatedSnapshot], timeout: 5)
        #expect(updateResult == .completed)
        #expect(snapshots.last == [wrappedSafe.address])
    }

    @Test func wrappedSafeRemainsEligibleWithoutPromotionOrCreator() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("safe4-wrapped-token-tests-\(UUID().uuidString).sqlite")
        let storage = try Safe4CustomTokenStorage(dbPool: DatabasePool(path: databaseURL.path))
        let wrappedSafe = token("0x0000000000000000000000000000000000001101", creator: "")

        try storage.synchronize(tokens: [wrappedSafe], ownedBy: owner, ownedAddresses: [], chainId: chainId)

        let stored = try #require(try storage.asset(address: wrappedSafe.address, chainId: chainId))
        #expect(!stored.isPromoted)
        #expect(stored.isEligible(forOwner: owner))
        #expect(stored.isEligible(forOwner: nil))
        #expect(token(wrappedSafe.address.uppercased(), creator: "").isEligible(forOwner: owner))
        // Matching only the address suffix must not bypass normal eligibility.
        #expect(!token("0x1111111111111111111111111111111111111101", creator: "").isEligible(forOwner: owner))
    }

    @Test func synchronizationPreservesVersionAndOnlyRemovesStaleOwnedTokens() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("safe4-token-sync-tests-\(UUID().uuidString).sqlite")
        let dbPool = try DatabasePool(path: databaseURL.path)
        let storage = try Safe4CustomTokenStorage(dbPool: dbPool)

        let existingOwnedToken = token(
            "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            creator: owner,
            type: 2,
            logoURI: "https://example.com/token.png",
            version: "SRC20-burnable-v1"
        )
        let caseVariantOwnedToken = token(existingOwnedToken.address.uppercased(), creator: owner)
        let staleOwnedToken = token("0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", creator: owner)
        let promotedToken = token("0xcccccccccccccccccccccccccccccccccccccccc", creator: "0x2222222222222222222222222222222222222222")
        let unpromotedToken = token("0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee", creator: "0x3333333333333333333333333333333333333333")
        promotedToken.isPromoted = true
        storage.save(tokens: [existingOwnedToken, caseVariantOwnedToken, staleOwnedToken, promotedToken, unpromotedToken])

        let refreshedOwnedToken = token(existingOwnedToken.address, creator: owner)
        let newOwnedToken = token("0xdddddddddddddddddddddddddddddddddddddddd", creator: owner)
        let refreshedPromotedToken = token(promotedToken.address, creator: promotedToken.creator)
        refreshedPromotedToken.isPromoted = true
        try storage.synchronize(
            tokens: [refreshedOwnedToken, newOwnedToken, refreshedPromotedToken, unpromotedToken],
            ownedBy: owner,
            ownedAddresses: [refreshedOwnedToken.address, newOwnedToken.address],
            chainId: chainId
        )

        #expect(try storage.asset(address: existingOwnedToken.address, chainId: chainId)?.version == "SRC20-burnable-v1")
        #expect(try storage.asset(address: existingOwnedToken.address, chainId: chainId)?.logoURI == "https://example.com/token.png")
        #expect(try storage.asset(address: existingOwnedToken.address, chainId: chainId)?.type == 2)
        #expect(storage.allTokens(chainId: chainId).filter { $0.address.lowercased() == existingOwnedToken.address }.count == 1)
        #expect(try storage.asset(address: staleOwnedToken.address, chainId: chainId) == nil)
        #expect(try storage.asset(address: newOwnedToken.address, chainId: chainId) != nil)
        #expect(try storage.asset(address: promotedToken.address, chainId: chainId) != nil)
        #expect(try storage.asset(address: unpromotedToken.address, chainId: chainId) != nil)
        #expect(try storage.asset(address: promotedToken.address, chainId: chainId)?.isPromoted == true)
        #expect(try storage.asset(address: unpromotedToken.address, chainId: chainId)?.isPromoted == false)
        #expect(try storage.asset(address: promotedToken.address, chainId: chainId)?.isEligible(forOwner: owner) == true)
        #expect(try storage.asset(address: unpromotedToken.address, chainId: chainId)?.isEligible(forOwner: owner) == false)
    }

    @Test func versionOnlyUpdatePreservesPromotionAndTokenMetadata() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("safe4-token-version-tests-\(UUID().uuidString).sqlite")
        let dbPool = try DatabasePool(path: databaseURL.path)
        let storage = try Safe4CustomTokenStorage(dbPool: dbPool)
        let promotedToken = token(
            "0xcccccccccccccccccccccccccccccccccccccccc",
            creator: "0x2222222222222222222222222222222222222222",
            type: 2,
            logoURI: "https://example.com/promoted.png"
        )
        promotedToken.isPromoted = true
        storage.save(token: promotedToken)

        try storage.updateVersions([promotedToken.address: "SRC20-burnable-v1"], chainId: chainId)

        let updatedToken = try storage.asset(address: promotedToken.address, chainId: chainId)
        #expect(updatedToken?.version == "SRC20-burnable-v1")
        #expect(updatedToken?.type == 2)
        #expect(updatedToken?.logoURI == "https://example.com/promoted.png")
        #expect(updatedToken?.isPromoted == true)
    }

    @Test func synchronizationForOneOwnerDoesNotDeleteAnotherOwnersToken() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("safe4-token-owner-tests-\(UUID().uuidString).sqlite")
        let dbPool = try DatabasePool(path: databaseURL.path)
        let storage = try Safe4CustomTokenStorage(dbPool: dbPool)
        let otherOwnersToken = token("0xffffffffffffffffffffffffffffffffffffffff", creator: "0x2222222222222222222222222222222222222222")
        otherOwnersToken.isPromoted = true
        storage.save(token: otherOwnersToken)

        try storage.synchronize(
            tokens: [],
            ownedBy: owner,
            ownedAddresses: [],
            chainId: chainId
        )

        #expect(try storage.asset(address: otherOwnersToken.address, chainId: chainId) != nil)
    }

    private func token(_ address: String, creator: String, type: Int? = nil, logoURI: String? = nil, version: String? = nil) -> Safe4CustomTokenRecord {
        Safe4CustomTokenRecord(
            address: address,
            symbol: "SRC",
            creator: creator,
            chainId: chainId,
            decimals: 18,
            name: "SRC Token",
            type: type,
            logoURI: logoURI,
            version: version
        )
    }
}
