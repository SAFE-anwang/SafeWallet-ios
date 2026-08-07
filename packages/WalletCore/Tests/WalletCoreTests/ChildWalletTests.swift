import Combine
import EvmKit
import MarketKit
import XCTest
@testable import WalletCore

final class ChildWalletTests: XCTestCase {
    private var storageURL: URL!
    private var cleanupURLs = [URL]()
    private var cancellables = Set<AnyCancellable>()
    private let mnemonicWords = [
        "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
        "abandon", "abandon", "abandon", "abandon", "abandon", "about",
    ]

    override func setUpWithError() throws {
        try super.setUpWithError()
        storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("child-wallet-tests-\(UUID().uuidString).json")
    }

    override func tearDownWithError() throws {
        cancellables.removeAll()
        for url in cleanupURLs + [storageURL].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
        }
        try super.tearDownWithError()
    }

    func testDerivationIndexRange() throws {
        XCTAssertThrowsError(try ChildWallet(parentAccountId: "parent", derivationIndex: 0, name: "zero")) { error in
            guard case ChildWalletError.invalidDerivationIndex = error else {
                return XCTFail("Expected invalidDerivationIndex, got \(error)")
            }
        }
        XCTAssertNoThrow(try ChildWallet(parentAccountId: "parent", derivationIndex: 1, name: "one"))
        XCTAssertNoThrow(try ChildWallet(parentAccountId: "parent", derivationIndex: 500, name: "max"))
        XCTAssertThrowsError(try ChildWallet(parentAccountId: "parent", derivationIndex: 501, name: "overflow")) { error in
            guard case ChildWalletError.invalidDerivationIndex = error else {
                return XCTFail("Expected invalidDerivationIndex, got \(error)")
            }
        }
    }

    func testRootModeBridgeDoesNotOverrideWalletIdentity() throws {
        let bridge = ChildWalletBridge(storage: ChildWalletFileStorage(url: storageURL))
        let account = mnemonicAccount(id: "parent")

        XCTAssertFalse(bridge.isChildWalletActive(account: account))
        XCTAssertNil(bridge.activeChildWalletId(account: account))
        XCTAssertEqual(try bridge.walletId(account: account, blockchainType: .ethereum), account.id)
        XCTAssertEqual(
            try bridge.kitCacheKey(account: account, blockchainType: .ethereum),
            ChildWalletKitCacheKey(accountId: account.id, childWalletId: nil, blockchainType: .ethereum)
        )
    }

    func testDisplayNameAppendsActiveChildWalletName() throws {
        let storage = ChildWalletFileStorage(url: storageURL)
        let bridge = ChildWalletBridge(storage: storage)
        let account = mnemonicAccount(id: "parent")

        XCTAssertEqual(bridge.displayName(account: account), "Mnemonic")

        let childWallet = try bridge.createNextChildWallet(parentAccountId: account.id)
        try bridge.setActiveChildWallet(parentAccountId: account.id, childWalletId: childWallet.id)

        XCTAssertEqual(bridge.displayName(account: account), "Mnemonic（子钱包 1）")
    }

    func testContextAccountIdIncludesActiveChildWallet() throws {
        let storage = ChildWalletFileStorage(url: storageURL)
        let bridge = ChildWalletBridge(storage: storage)
        let account = mnemonicAccount(id: "parent")
        let childWallet = try bridge.createNextChildWallet(parentAccountId: account.id, name: "one")

        XCTAssertEqual(bridge.contextAccountId(account: account), account.id)

        try bridge.setActiveChildWallet(parentAccountId: account.id, childWalletId: childWallet.id)
        XCTAssertEqual(bridge.contextAccountId(account: account), [account.id, "child", childWallet.id].joined(separator: ":"))

        try bridge.setActiveChildWallet(parentAccountId: account.id, childWalletId: nil)
        XCTAssertEqual(bridge.contextAccountId(account: account), account.id)
    }

    func testChildModeWalletIdentityIsIsolatedByChildWalletAndBlockchain() throws {
        let storage = ChildWalletFileStorage(url: storageURL)
        let bridge = ChildWalletBridge(storage: storage)
        let account = mnemonicAccount(id: "parent")
        let first = try bridge.createNextChildWallet(parentAccountId: account.id, name: "one")
        let second = try bridge.createNextChildWallet(parentAccountId: account.id, name: "two")

        try bridge.setActiveChildWallet(parentAccountId: account.id, childWalletId: first.id)
        let firstEthereumWalletId = try bridge.walletId(account: account, blockchainType: .ethereum)
        let firstSafe4WalletId = try bridge.walletId(account: account, blockchainType: .safe4)
        let firstCacheKey = try bridge.kitCacheKey(account: account, blockchainType: .ethereum)

        try bridge.setActiveChildWallet(parentAccountId: account.id, childWalletId: second.id)
        let secondEthereumWalletId = try bridge.walletId(account: account, blockchainType: .ethereum)
        let secondCacheKey = try bridge.kitCacheKey(account: account, blockchainType: .ethereum)

        XCTAssertNotEqual(firstEthereumWalletId, account.id)
        XCTAssertNotEqual(firstEthereumWalletId, firstSafe4WalletId)
        XCTAssertNotEqual(firstEthereumWalletId, secondEthereumWalletId)
        XCTAssertEqual(firstCacheKey.childWalletId, first.id)
        XCTAssertEqual(secondCacheKey.childWalletId, second.id)
    }

    func testChildModeWalletIdIsFileNameSafeAndDeterministic() throws {
        let storage = ChildWalletFileStorage(url: storageURL)
        let bridge = ChildWalletBridge(storage: storage)
        let account = mnemonicAccount(id: "parent:with/slash")
        let childWallet = try bridge.createNextChildWallet(parentAccountId: account.id, name: "one")

        try bridge.setActiveChildWallet(parentAccountId: account.id, childWalletId: childWallet.id)

        let ethereumWalletId = try bridge.walletId(account: account, blockchainType: .ethereum)
        let ethereumWalletIdAgain = try bridge.walletId(account: account, blockchainType: .ethereum)
        let safe4WalletId = try bridge.walletId(account: account, blockchainType: .safe4)

        XCTAssertEqual(ethereumWalletId, ethereumWalletIdAgain)
        XCTAssertNotEqual(ethereumWalletId, account.id)
        XCTAssertNotEqual(ethereumWalletId, safe4WalletId)
        XCTAssertNil(ethereumWalletId.range(of: #"[^A-Za-z0-9._-]"#, options: .regularExpression))
        XCTAssertFalse(ethereumWalletId.contains(":"))
        XCTAssertFalse(ethereumWalletId.contains("/"))
    }

    func testChildEvmAddressCanUseInjectedChainWithoutCoreSharedLookup() throws {
        let storage = ChildWalletFileStorage(url: storageURL)
        let bridge = ChildWalletBridge(storage: storage)
        let account = mnemonicAccount(id: "parent")
        let childWallet = try bridge.createNextChildWallet(parentAccountId: account.id, name: "one")

        try bridge.setActiveChildWallet(parentAccountId: account.id, childWalletId: childWallet.id)

        let address = try bridge.evmAddress(account: account, blockchainType: .ethereum, chain: .ethereum)
        let expectedAddress = try ChildWalletDerivationService().evmAddress(account: account, childWallet: childWallet, chain: .ethereum)

        XCTAssertEqual(address?.hex, expectedAddress.hex)
    }

    func testSettingActiveChildWalletPublishesContextChanges() throws {
        let storage = ChildWalletFileStorage(url: storageURL)
        let bridge = ChildWalletBridge(storage: storage)
        let childWallet = try bridge.createNextChildWallet(parentAccountId: "parent", name: "one")
        var events = [ChildWalletBridge.ActiveChildWalletChange]()

        bridge.activeChildWalletChangedPublisher
            .sink { events.append($0) }
            .store(in: &cancellables)

        try bridge.setActiveChildWallet(parentAccountId: "parent", childWalletId: childWallet.id)
        try bridge.setActiveChildWallet(parentAccountId: "parent", childWalletId: nil)

        XCTAssertEqual(
            events,
            [
                ChildWalletBridge.ActiveChildWalletChange(parentAccountId: "parent", childWalletId: childWallet.id),
                ChildWalletBridge.ActiveChildWalletChange(parentAccountId: "parent", childWalletId: nil),
            ]
        )
    }

    func testTronChildDerivationIsStableAndIndexSpecific() throws {
        let account = mnemonicAccount(id: "parent")
        let service = ChildWalletDerivationService()
        let first = try ChildWallet(parentAccountId: account.id, derivationIndex: 1, name: "one")
        let firstAgain = try ChildWallet(parentAccountId: account.id, derivationIndex: 1, name: "one-again")
        let second = try ChildWallet(parentAccountId: account.id, derivationIndex: 2, name: "two")

        let firstAddress = try service.tronAddress(account: account, childWallet: first)
        let firstAddressAgain = try service.tronAddress(account: account, childWallet: firstAgain)
        let secondAddress = try service.tronAddress(account: account, childWallet: second)

        XCTAssertEqual(firstAddress.base58, firstAddressAgain.base58)
        XCTAssertNotEqual(firstAddress.base58, secondAddress.base58)
    }

    func testParentStateHighestKnownIndexUsesAllocatedIndexAndLegacyDetectedIndex() throws {
        var state = ChildWalletParentState.fresh(parentAccountId: "parent")

        XCTAssertEqual(state.highestKnownIndex, 0)

        state.recordAllocated(index: 3)
        XCTAssertEqual(state.highestKnownIndex, 3)

        let legacyJson = """
        {
          "parentAccountId": "parent",
          "highestAllocatedIndex": 3,
          "highestDetectedIndex": 9,
          "createdAt": 1,
          "updatedAt": 2
        }
        """
        let legacyState = try JSONDecoder().decode(ChildWalletParentState.self, from: Data(legacyJson.utf8))
        XCTAssertEqual(legacyState.highestKnownIndex, 9)
    }

    func testChildWalletDecodesLegacyJsonWithoutCreationSource() throws {
        let json = """
        {
          "id": "child",
          "parentAccountId": "parent",
          "derivationIndex": 1,
          "name": "one",
          "isHidden": false,
          "createdAt": 1
        }
        """

        let childWallet = try JSONDecoder().decode(ChildWallet.self, from: Data(json.utf8))

        XCTAssertNil(childWallet.creationSource)
    }

    func testStorageRejectsDuplicateDerivationIndexForSameParent() throws {
        let storage = ChildWalletFileStorage(url: storageURL)
        try storage.save(childWallet: try ChildWallet(id: "child-1", parentAccountId: "parent", derivationIndex: 1, name: "one"))

        XCTAssertThrowsError(
            try storage.save(childWallet: try ChildWallet(id: "child-2", parentAccountId: "parent", derivationIndex: 1, name: "duplicate"))
        ) { error in
            guard case ChildWalletError.duplicateDerivationIndex = error else {
                return XCTFail("Expected duplicateDerivationIndex, got \(error)")
            }
        }
    }

    func testActiveChildRequiresVisibleChildOwnedByParent() throws {
        let storage = ChildWalletFileStorage(url: storageURL)
        let visible = try ChildWallet(id: "visible", parentAccountId: "parent", derivationIndex: 1, name: "visible")
        let hidden = try ChildWallet(id: "hidden", parentAccountId: "parent", derivationIndex: 2, name: "hidden", isHidden: true)
        try storage.save(childWallet: visible)
        try storage.save(childWallet: hidden)

        try storage.setActiveChildWallet(parentAccountId: "parent", childWalletId: visible.id)
        XCTAssertEqual(try storage.activeChildWallet(parentAccountId: "parent")?.id, visible.id)

        XCTAssertThrowsError(try storage.setActiveChildWallet(parentAccountId: "other-parent", childWalletId: visible.id))
        XCTAssertThrowsError(try storage.setActiveChildWallet(parentAccountId: "parent", childWalletId: hidden.id))
    }

    func testEnabledWalletsRequireChildOwnership() throws {
        let storage = ChildWalletFileStorage(url: storageURL)
        let child = try ChildWallet(id: "child", parentAccountId: "parent-a", derivationIndex: 1, name: "one")
        try storage.save(childWallet: child)

        try storage.save(
            enabledWallets: [
                EnabledWallet(tokenQueryId: "ethereum|native", accountId: "parent-a", coinName: "Ethereum", coinCode: "ETH", tokenDecimals: 18),
            ],
            childWalletId: child.id,
            parentAccountId: "parent-a"
        )

        XCTAssertEqual(try storage.enabledWallets(childWalletId: child.id, parentAccountId: "parent-a").count, 1)
        XCTAssertTrue(
            try storage.enabledWallets(childWalletId: child.id, parentAccountId: "parent-b").isEmpty,
            "A child wallet's enabled tokens must not be returned for another parent account."
        )
        XCTAssertThrowsError(try storage.save(enabledWallets: [], childWalletId: child.id, parentAccountId: "parent-b"))
        XCTAssertThrowsError(try storage.delete(tokenQueryIds: ["ethereum|native"], childWalletId: child.id, parentAccountId: "parent-b"))
    }

    func testSavingEnabledWalletsDoesNotOverwriteOtherChildWallets() throws {
        let storage = ChildWalletFileStorage(url: storageURL)
        let first = try ChildWallet(id: "child-1", parentAccountId: "parent", derivationIndex: 1, name: "one")
        let second = try ChildWallet(id: "child-2", parentAccountId: "parent", derivationIndex: 2, name: "two")
        try storage.save(childWallet: first)
        try storage.save(childWallet: second)

        try storage.save(
            enabledWallets: [
                EnabledWallet(tokenQueryId: "ethereum|native", accountId: "parent", coinName: "Ethereum", coinCode: "ETH", tokenDecimals: 18),
            ],
            childWalletId: first.id,
            parentAccountId: "parent"
        )
        try storage.save(
            enabledWallets: [
                EnabledWallet(tokenQueryId: "tron|native", accountId: "parent", coinName: "TRON", coinCode: "TRX", tokenDecimals: 6),
            ],
            childWalletId: second.id,
            parentAccountId: "parent"
        )

        XCTAssertEqual(try storage.enabledWallets(childWalletId: first.id, parentAccountId: "parent").map(\.tokenQueryId), ["ethereum|native"])
        XCTAssertEqual(try storage.enabledWallets(childWalletId: second.id, parentAccountId: "parent").map(\.tokenQueryId), ["tron|native"])
    }

    func testSavingEnabledWalletsReplacesMatchingTokenForSameChildWallet() throws {
        let storage = ChildWalletFileStorage(url: storageURL)
        let child = try ChildWallet(id: "child", parentAccountId: "parent", derivationIndex: 1, name: "one")
        try storage.save(childWallet: child)

        try storage.save(
            enabledWallets: [
                EnabledWallet(tokenQueryId: "ethereum|native", accountId: "parent", coinName: "Ethereum", coinCode: "ETH", tokenDecimals: 18),
            ],
            childWalletId: child.id,
            parentAccountId: "parent"
        )
        try storage.save(
            enabledWallets: [
                EnabledWallet(tokenQueryId: "ethereum|native", accountId: "parent", coinName: "Ethereum Updated", coinCode: "ETH", tokenDecimals: 18),
            ],
            childWalletId: child.id,
            parentAccountId: "parent"
        )

        let enabledWallets = try storage.enabledWallets(childWalletId: child.id, parentAccountId: "parent")
        XCTAssertEqual(enabledWallets.count, 1)
        XCTAssertEqual(enabledWallets.first?.coinName, "Ethereum Updated")
    }

    func testGRDBStoragePersistsChildWalletStateAndEnabledWallets() throws {
        let dbURL = sqliteURL()
        let storage = try ChildWalletGRDBStorage(url: dbURL)
        let childWallet = try ChildWallet(id: "child", parentAccountId: "parent", derivationIndex: 1, name: "one")
        var parentState = ChildWalletParentState.fresh(parentAccountId: "parent")
        parentState.recordAllocated(index: 1)

        try storage.save(childWallet: childWallet)
        try storage.setActiveChildWallet(parentAccountId: "parent", childWalletId: childWallet.id)
        try storage.save(parentState: parentState)
        try storage.save(
            enabledWallets: [
                EnabledWallet(tokenQueryId: "safe4|native", accountId: "parent", coinName: "SAFE4", coinCode: "SAFE", tokenDecimals: 18),
            ],
            childWalletId: childWallet.id,
            parentAccountId: "parent"
        )

        let reopenedStorage = try ChildWalletGRDBStorage(url: dbURL)

        XCTAssertEqual(try reopenedStorage.childWallets(parentAccountId: "parent").map(\.id), ["child"])
        XCTAssertEqual(try reopenedStorage.activeChildWallet(parentAccountId: "parent")?.id, "child")
        XCTAssertEqual(try reopenedStorage.parentState(parentAccountId: "parent")?.highestKnownIndex, 1)
        XCTAssertEqual(try reopenedStorage.enabledWallets(childWalletId: childWallet.id, parentAccountId: "parent").map(\.tokenQueryId), ["safe4|native"])
    }

    func testGRDBStorageMigratesLegacyJsonWhenDatabaseIsEmpty() throws {
        let jsonStorage = ChildWalletFileStorage(url: storageURL)
        let childWallet = try ChildWallet(id: "child", parentAccountId: "parent", derivationIndex: 2, name: "two")
        var parentState = ChildWalletParentState.fresh(parentAccountId: "parent")
        parentState.recordAllocated(index: 2)
        try jsonStorage.save(childWallet: childWallet)
        try jsonStorage.save(parentState: parentState)
        try jsonStorage.setActiveChildWallet(parentAccountId: "parent", childWalletId: childWallet.id)
        try jsonStorage.save(
            enabledWallets: [
                EnabledWallet(tokenQueryId: "tron|native", accountId: "parent", coinName: "TRON", coinCode: "TRX", tokenDecimals: 6),
            ],
            childWalletId: childWallet.id,
            parentAccountId: "parent"
        )

        let storage = try ChildWalletGRDBStorage(url: sqliteURL(), legacyFileStorage: jsonStorage)

        XCTAssertEqual(try storage.childWallets(parentAccountId: "parent").map(\.derivationIndex), [2])
        XCTAssertEqual(try storage.activeChildWallet(parentAccountId: "parent")?.id, childWallet.id)
        XCTAssertEqual(try storage.parentState(parentAccountId: "parent")?.highestKnownIndex, 2)
        XCTAssertEqual(try storage.enabledWallets(childWalletId: childWallet.id, parentAccountId: "parent").map(\.tokenQueryId), ["tron|native"])
    }

    func testNextDerivationIndexUsesHighestKnownIndex() throws {
        let storage = ChildWalletFileStorage(url: storageURL)
        let bridge = ChildWalletBridge(storage: storage)

        var parentState = ChildWalletParentState.fresh(parentAccountId: "parent")
        parentState.recordAllocated(index: 5)
        try bridge.save(parentState: parentState)

        XCTAssertEqual(try bridge.nextDerivationIndex(parentAccountId: "parent"), 6)
    }

    func testNextDerivationIndexCountsHiddenWallets() throws {
        let storage = ChildWalletFileStorage(url: storageURL)
        let bridge = ChildWalletBridge(storage: storage)

        try storage.save(childWallet: try ChildWallet(id: "hidden", parentAccountId: "parent", derivationIndex: 5, name: "hidden", isHidden: true))

        XCTAssertEqual(try storage.childWallets(parentAccountId: "parent").map(\.derivationIndex), [])
        XCTAssertEqual(try storage.allChildWallets(parentAccountId: "parent").map(\.derivationIndex), [5])
        XCTAssertEqual(try bridge.allChildWallets(parentAccountId: "parent").map(\.derivationIndex), [5])
        XCTAssertEqual(try bridge.nextDerivationIndex(parentAccountId: "parent"), 6)
    }

    func testCreateChildWalletDoesNotInitializeDefaultEnabledWallets() throws {
        let storage = ChildWalletFileStorage(url: storageURL)
        let bridge = ChildWalletBridge(storage: storage)

        let childWallet = try bridge.createNextChildWallet(parentAccountId: "parent", name: "one")

        XCTAssertTrue(try storage.enabledWallets(childWalletId: childWallet.id, parentAccountId: "parent").isEmpty)
    }

    func testChildSaveDoesNotConsumeUnsupportedEnabledWallets() throws {
        let storage = ChildWalletFileStorage(url: storageURL)
        let bridge = ChildWalletBridge(storage: storage)
        let account = mnemonicAccount(id: "parent")
        let childWallet = try bridge.createNextChildWallet(parentAccountId: account.id, name: "one")
        try bridge.setActiveChildWallet(parentAccountId: account.id, childWalletId: childWallet.id)

        let unhandled = try bridge.saveAndReturnUnhandled(
            enabledWallets: [
                EnabledWallet(tokenQueryId: BlockchainType.ton.defaultTokenQuery.id, accountId: account.id, coinName: "Toncoin", coinCode: "TON", tokenDecimals: 9),
            ],
            account: account
        )

        XCTAssertEqual(unhandled?.map(\.tokenQueryId), [BlockchainType.ton.defaultTokenQuery.id])
        XCTAssertTrue(try storage.enabledWallets(childWalletId: childWallet.id, parentAccountId: account.id).isEmpty)
    }

    func testChildSaveSplitsSupportedAndUnsupportedEnabledWallets() throws {
        let storage = ChildWalletFileStorage(url: storageURL)
        let bridge = ChildWalletBridge(storage: storage)
        let account = mnemonicAccount(id: "parent")
        let childWallet = try bridge.createNextChildWallet(parentAccountId: account.id, name: "one")
        try bridge.setActiveChildWallet(parentAccountId: account.id, childWalletId: childWallet.id)

        let unhandled = try bridge.saveAndReturnUnhandled(
            enabledWallets: [
                EnabledWallet(tokenQueryId: BlockchainType.ethereum.defaultTokenQuery.id, accountId: account.id, coinName: "Ethereum", coinCode: "ETH", tokenDecimals: 18),
                EnabledWallet(tokenQueryId: BlockchainType.solana.defaultTokenQuery.id, accountId: account.id, coinName: "Solana", coinCode: "SOL", tokenDecimals: 9),
            ],
            account: account
        )

        XCTAssertEqual(unhandled?.map(\.tokenQueryId), [BlockchainType.solana.defaultTokenQuery.id])
        XCTAssertEqual(
            try storage.enabledWallets(childWalletId: childWallet.id, parentAccountId: account.id).map(\.tokenQueryId),
            [BlockchainType.ethereum.defaultTokenQuery.id]
        )
    }

    func testSelectingChildWalletRemovesOnlyLegacyAutoSeededDefaultWallets() throws {
        let storage = ChildWalletFileStorage(url: storageURL)
        let bridge = ChildWalletBridge(storage: storage)
        let childWallet = try bridge.createNextChildWallet(parentAccountId: "parent", name: "one")
        let sibling = try bridge.createNextChildWallet(parentAccountId: "parent", name: "two")
        try storage.insert(
            enabledWallets: [
                ChildEnabledWallet(parentAccountId: "parent", childWalletId: childWallet.id, tokenQueryId: BlockchainType.ethereum.defaultTokenQuery.id),
                ChildEnabledWallet(parentAccountId: "parent", childWalletId: sibling.id, tokenQueryId: BlockchainType.tron.defaultTokenQuery.id),
                ChildEnabledWallet(
                    parentAccountId: "parent",
                    childWalletId: childWallet.id,
                    tokenQueryId: BlockchainType.safe4.defaultTokenQuery.id,
                    coinName: "SAFE4",
                    coinCode: "SAFE",
                    tokenDecimals: 18
                ),
                ChildEnabledWallet(parentAccountId: "parent", childWalletId: childWallet.id, tokenQueryId: "safe4|eip20|custom-token"),
            ],
            parentAccountId: "parent"
        )

        try bridge.setActiveChildWallet(parentAccountId: "parent", childWalletId: childWallet.id)

        let enabledWallets = try storage.enabledWallets(childWalletId: childWallet.id, parentAccountId: "parent")
        XCTAssertEqual(Set(enabledWallets.map(\.tokenQueryId)), [BlockchainType.safe4.defaultTokenQuery.id, "safe4|eip20|custom-token"])
        XCTAssertTrue(try storage.enabledWallets(childWalletId: sibling.id, parentAccountId: "parent").isEmpty)
        XCTAssertEqual(try bridge.parentState(parentAccountId: "parent").legacyAutoSeededEnabledWalletsCleaned, true)
    }

    func testLegacyAutoSeededDefaultWalletCleanupRunsOncePerParent() throws {
        let storage = ChildWalletFileStorage(url: storageURL)
        let bridge = ChildWalletBridge(storage: storage)
        let childWallet = try bridge.createNextChildWallet(parentAccountId: "parent", name: "one")
        try storage.insert(
            enabledWallets: [
                ChildEnabledWallet(parentAccountId: "parent", childWalletId: childWallet.id, tokenQueryId: BlockchainType.ethereum.defaultTokenQuery.id),
            ],
            parentAccountId: "parent"
        )

        try bridge.setActiveChildWallet(parentAccountId: "parent", childWalletId: childWallet.id)
        XCTAssertTrue(try storage.enabledWallets(childWalletId: childWallet.id, parentAccountId: "parent").isEmpty)

        try storage.insert(
            enabledWallets: [
                ChildEnabledWallet(parentAccountId: "parent", childWalletId: childWallet.id, tokenQueryId: BlockchainType.ethereum.defaultTokenQuery.id),
            ],
            parentAccountId: "parent"
        )

        try bridge.setActiveChildWallet(parentAccountId: "parent", childWalletId: childWallet.id)
        XCTAssertEqual(try storage.enabledWallets(childWalletId: childWallet.id, parentAccountId: "parent").map(\.tokenQueryId), [BlockchainType.ethereum.defaultTokenQuery.id])
    }

    func testRootModeIgnoresUnreadableChildWalletStorage() throws {
        try Data("{".utf8).write(to: storageURL, options: .atomic)
        let bridge = ChildWalletBridge(storage: ChildWalletFileStorage(url: storageURL))
        let account = mnemonicAccount(id: "parent")

        XCTAssertFalse(bridge.isChildWalletActive(account: account))
        XCTAssertNil(bridge.activeChildWalletId(account: account))
        XCTAssertEqual(try bridge.kitCacheKey(account: account, blockchainType: .ethereum).childWalletId, nil)
        XCTAssertEqual(try bridge.walletId(account: account, blockchainType: .ethereum), account.id)
        XCTAssertNil(try bridge.evmAddress(account: account, blockchainType: .ethereum))
    }

    func testLegacyActiveChildWalletSelectionMigratesToActiveStateStore() throws {
        let storage = ChildWalletFileStorage(url: storageURL)
        let activeStateStore = ChildWalletInMemoryActiveStateStore()
        let bridge = ChildWalletBridge(storage: storage, activeStateStore: activeStateStore)
        let account = mnemonicAccount(id: "parent")
        let childWallet = try ChildWallet(id: "child", parentAccountId: account.id, derivationIndex: 3, name: "three")
        try storage.save(childWallet: childWallet)
        try storage.setActiveChildWallet(parentAccountId: account.id, childWalletId: childWallet.id)

        XCTAssertEqual(bridge.activeChildWalletId(account: account), childWallet.id)
        XCTAssertEqual(activeStateStore.activeChildWalletId(parentAccountId: account.id), childWallet.id)
        XCTAssertEqual(
            try bridge.walletId(account: account, blockchainType: .safe4),
            "cw-p706172656e74-i3-c7361666534"
        )
    }

    func testActiveChildWalletIdentityFailsClosedWhenStorageIsUnreadable() throws {
        try Data("{".utf8).write(to: storageURL, options: .atomic)
        let activeStateStore = ChildWalletInMemoryActiveStateStore()
        activeStateStore.setActiveChildWalletId("child", parentAccountId: "parent")
        let bridge = ChildWalletBridge(storage: ChildWalletFileStorage(url: storageURL), activeStateStore: activeStateStore)
        let account = mnemonicAccount(id: "parent")

        XCTAssertTrue(bridge.isChildWalletActive(account: account))
        XCTAssertEqual(bridge.activeChildWalletId(account: account), "child")
        XCTAssertThrowsError(try bridge.kitCacheKey(account: account, blockchainType: .ethereum)) { error in
            guard case ChildWalletError.storageUnavailable = error else {
                return XCTFail("Expected storageUnavailable, got \(error)")
            }
        }
        XCTAssertThrowsError(try bridge.walletId(account: account, blockchainType: .ethereum)) { error in
            guard case ChildWalletError.storageUnavailable = error else {
                return XCTFail("Expected storageUnavailable, got \(error)")
            }
        }
        XCTAssertThrowsError(try bridge.evmAddress(account: account, blockchainType: .ethereum)) { error in
            guard case ChildWalletError.storageUnavailable = error else {
                return XCTFail("Expected storageUnavailable, got \(error)")
            }
        }
    }

    func testStaleActiveChildWalletIdClearsWhenChildIsMissing() throws {
        let storage = ChildWalletFileStorage(url: storageURL)
        let activeStateStore = ChildWalletInMemoryActiveStateStore()
        activeStateStore.setActiveChildWalletId("missing-child", parentAccountId: "parent")
        let bridge = ChildWalletBridge(storage: storage, activeStateStore: activeStateStore)
        let account = mnemonicAccount(id: "parent")

        XCTAssertNil(bridge.activeChildWalletId(account: account))
        XCTAssertFalse(bridge.isChildWalletActive(account: account))
        XCTAssertNil(activeStateStore.activeChildWalletId(parentAccountId: account.id))
        XCTAssertEqual(try bridge.walletId(account: account, blockchainType: .ethereum), account.id)
    }

    func testHiddenActiveChildWalletIdClearsAndReturnsRootMode() throws {
        let storage = ChildWalletFileStorage(url: storageURL)
        let activeStateStore = ChildWalletInMemoryActiveStateStore()
        let childWallet = try ChildWallet(id: "hidden-child", parentAccountId: "parent", derivationIndex: 1, name: "hidden", isHidden: true)
        try storage.save(childWallet: childWallet)
        activeStateStore.setActiveChildWalletId(childWallet.id, parentAccountId: "parent")
        let bridge = ChildWalletBridge(storage: storage, activeStateStore: activeStateStore)
        let account = mnemonicAccount(id: "parent")

        XCTAssertNil(bridge.activeChildWalletId(account: account))
        XCTAssertFalse(bridge.isChildWalletActive(account: account))
        XCTAssertNil(activeStateStore.activeChildWalletId(parentAccountId: account.id))
        XCTAssertEqual(try bridge.walletId(account: account, blockchainType: .safe4), account.id)
    }

    func testSelectingRootClearsActiveChildEvenWhenStorageIsUnreadable() throws {
        let activeStateStore = ChildWalletInMemoryActiveStateStore()
        activeStateStore.setActiveChildWalletId("child", parentAccountId: "parent")
        try Data("{".utf8).write(to: storageURL, options: .atomic)
        let bridge = ChildWalletBridge(storage: ChildWalletFileStorage(url: storageURL), activeStateStore: activeStateStore)

        try bridge.setActiveChildWallet(parentAccountId: "parent", childWalletId: nil)

        XCTAssertNil(bridge.activeChildWalletId(parentAccountId: "parent"))
    }

    func testRenameChildWalletTrimsNameAndRejectsEmptyName() throws {
        let bridge = ChildWalletBridge(storage: ChildWalletFileStorage(url: storageURL))
        let childWallet = try bridge.createNextChildWallet(parentAccountId: "parent", name: "one")

        let renamed = try bridge.renameChildWallet(parentAccountId: "parent", childWalletId: childWallet.id, name: "  Spending  ")

        XCTAssertEqual(renamed.name, "Spending")
        XCTAssertEqual(try bridge.childWallets(parentAccountId: "parent").first?.name, "Spending")
        XCTAssertThrowsError(try bridge.renameChildWallet(parentAccountId: "parent", childWalletId: childWallet.id, name: "   ")) { error in
            guard case ChildWalletError.invalidName = error else {
                return XCTFail("Expected invalidName, got \(error)")
            }
        }
    }

    func testHideChildWalletKeepsIndexReservedAndClearsActiveChild() throws {
        let storage = ChildWalletFileStorage(url: storageURL)
        let bridge = ChildWalletBridge(storage: storage)
        let childWallet = try ChildWallet(parentAccountId: "parent", derivationIndex: 3, name: "three")
        try storage.save(childWallet: childWallet)
        try bridge.setActiveChildWallet(parentAccountId: "parent", childWalletId: childWallet.id)

        try bridge.hideChildWallet(parentAccountId: "parent", childWalletId: childWallet.id)

        XCTAssertNil(bridge.activeChildWalletId(parentAccountId: "parent"))
        XCTAssertTrue(try bridge.childWallets(parentAccountId: "parent").isEmpty)
        XCTAssertEqual(try storage.allChildWallets(parentAccountId: "parent").map(\.derivationIndex), [3])
        XCTAssertEqual(try bridge.nextDerivationIndex(parentAccountId: "parent"), 4)
    }

    func testHidingActiveChildWalletPublishesNilActiveChildChange() throws {
        let storage = ChildWalletFileStorage(url: storageURL)
        let bridge = ChildWalletBridge(storage: storage)
        let childWallet = try bridge.createNextChildWallet(parentAccountId: "parent", name: "one")
        var events = [ChildWalletBridge.ActiveChildWalletChange]()

        bridge.activeChildWalletChangedPublisher
            .sink { events.append($0) }
            .store(in: &cancellables)

        try bridge.setActiveChildWallet(parentAccountId: "parent", childWalletId: childWallet.id)
        try bridge.hideChildWallet(parentAccountId: "parent", childWalletId: childWallet.id)

        XCTAssertEqual(
            events,
            [
                ChildWalletBridge.ActiveChildWalletChange(parentAccountId: "parent", childWalletId: childWallet.id),
                ChildWalletBridge.ActiveChildWalletChange(parentAccountId: "parent", childWalletId: nil),
            ]
        )
    }

    func testHideChildWalletKeepsOtherParentActiveChild() throws {
        let storage = ChildWalletFileStorage(url: storageURL)
        let bridge = ChildWalletBridge(storage: storage)
        let first = try bridge.createNextChildWallet(parentAccountId: "parent-a", name: "one")
        let second = try bridge.createNextChildWallet(parentAccountId: "parent-b", name: "one")
        try bridge.setActiveChildWallet(parentAccountId: "parent-a", childWalletId: first.id)
        try bridge.setActiveChildWallet(parentAccountId: "parent-b", childWalletId: second.id)

        try bridge.hideChildWallet(parentAccountId: "parent-a", childWalletId: first.id)

        XCTAssertNil(bridge.activeChildWalletId(parentAccountId: "parent-a"))
        XCTAssertEqual(bridge.activeChildWalletId(parentAccountId: "parent-b"), second.id)
    }

    func testLegacyEvmKitDatabaseCleanerRemovesOnlyLegacyChildWalletDatabasesForParent() throws {
        let directoryURL = temporaryDirectoryURL()
        let cleaner = ChildWalletLegacyEvmKitDatabaseCleaner(directoryURLProvider: { directoryURL })
        let filenamesToCreate = [
            "api-parent:child:1:ethereum-1.sqlite",
            "transactions-parent:child:2:binance-smart-chain-56.sqlite",
            "eip20-parent:child:1:ethereum-1.sqlite-wal",
            "transactions-other-parent:child:1:ethereum-1.sqlite",
            "transactions-parent-1.sqlite",
            "transactions-cw-pparent-i1-cethereum.sqlite",
        ]

        for filename in filenamesToCreate {
            try Data(filename.utf8).write(to: directoryURL.appendingPathComponent(filename))
        }

        let removedCount = try cleaner.cleanLegacyChildWalletDatabases(parentAccountId: "parent")

        XCTAssertEqual(removedCount, 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent("api-parent:child:1:ethereum-1.sqlite").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent("transactions-parent:child:2:binance-smart-chain-56.sqlite").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent("eip20-parent:child:1:ethereum-1.sqlite-wal").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent("transactions-other-parent:child:1:ethereum-1.sqlite").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent("transactions-parent-1.sqlite").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent("transactions-cw-pparent-i1-cethereum.sqlite").path))
    }

    func testLegacyEvmKitDatabaseCleanerRemovesAllLegacyChildWalletDatabasesAcrossKitDirectories() throws {
        let evmDirectoryURL = temporaryDirectoryURL()
        let tronDirectoryURL = temporaryDirectoryURL()
        let cleaner = ChildWalletLegacyEvmKitDatabaseCleaner(directoryURLProviders: [
            { evmDirectoryURL },
            { tronDirectoryURL },
        ])

        let evmLegacy = evmDirectoryURL.appendingPathComponent("transactions-parent:child:1:ethereum-1.sqlite")
        let evmCurrent = evmDirectoryURL.appendingPathComponent("transactions-cw-pparent-i1-cethereum.sqlite")
        let tronLegacy = tronDirectoryURL.appendingPathComponent("transactions-storage-parent:child:1:tron-mainNet.sqlite")
        let tronCurrent = tronDirectoryURL.appendingPathComponent("transactions-storage-cw-pparent-i1-ctron-mainNet.sqlite")

        for url in [evmLegacy, evmCurrent, tronLegacy, tronCurrent] {
            try Data(url.lastPathComponent.utf8).write(to: url)
        }

        let removedCount = try cleaner.cleanAllLegacyChildWalletDatabases()

        XCTAssertEqual(removedCount, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: evmLegacy.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tronLegacy.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: evmCurrent.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tronCurrent.path))
    }

    private func mnemonicAccount(id: String) -> Account {
        Account(
            id: id,
            level: 0,
            name: "Mnemonic",
            type: .mnemonic(words: mnemonicWords, salt: "", bip39Compliant: true),
            origin: .created,
            backedUp: false,
            fileBackedUp: false
        )
    }

    private func sqliteURL() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("child-wallet-tests-\(UUID().uuidString).sqlite")
        cleanupURLs.append(url)
        return url
    }

    private func temporaryDirectoryURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("child-wallet-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        cleanupURLs.append(url)
        return url
    }
}
