import BigInt
import CryptoSwift
import Foundation
import Web3Core
import web3swift
import XCTest

@testable import WalletCore

final class SRC721ServiceReadTests: XCTestCase {
    func testSupplyReadsDoNotOverlapAndKeepTheirOwnResults() async throws {
        for type in [SRC721ContractType.standard, .burnable, .generic] {
            let rpc = SRC721ReadRPC()
            defer { rpc.close() }

            // Exercise the binding path used by the contract manager as well.
            let state = try await rpc.service().binding(contractAddress: rpc.address).supplyState(type: type)

            XCTAssertEqual(state.totalSupply, 7)
            XCTAssertEqual(state.remainSupply, 91)
            XCTAssertEqual(state.burnedCount, 2)
            XCTAssertEqual(rpc.maximumInFlight, 1, "Reads must not overlap on the same Web3 instance: \(type)")
            XCTAssertEqual(rpc.requestCount, 3)
        }
    }

    func testDetailReadsDoNotOverlapAndDecodeEveryField() async throws {
        for type in [SRC721ContractType.standard, .burnable, .generic] {
            let rpc = SRC721ReadRPC()
            defer { rpc.close() }

            let state = try await rpc.service().state(type: type)

            XCTAssertEqual(state.name, "Collection")
            XCTAssertEqual(state.symbol, "NFT")
            XCTAssertEqual(state.ownerAddress.lowercased(), rpc.address)
            XCTAssertEqual(state.baseURI, "ipfs://collection/")
            XCTAssertEqual(state.maxSupply, 100)
            XCTAssertEqual(state.totalSupply, 7)
            XCTAssertEqual(state.remainSupply, 91)
            XCTAssertEqual(state.burnedCount, 2)
            XCTAssertEqual(state.mintPrice, 3)
            XCTAssertEqual(state.orgName, "Issuer")
            XCTAssertEqual(state.description, "Description")
            XCTAssertEqual(state.officialURL, "https://example.com")
            XCTAssertEqual(state.whitePaperURL, "https://example.com/paper")
            XCTAssertEqual(state.logo, Data([1, 2, 3]))
            XCTAssertEqual(rpc.maximumInFlight, 1, "Reads must not overlap on the same Web3 instance: \(type)")
            XCTAssertEqual(rpc.requestCount, 14)
        }
    }

    @MainActor
    func testLegacyFTPReadAndUnchangedURIEditValidation() async throws {
        let legacy = "ftp://example.com/legacy/"
        let rpc = SRC721ReadRPC(baseURI: legacy)
        defer { rpc.close() }
        let suite = "SRC721LegacyFTPTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let record = SRC721ContractRecord(
            accountId: "test", chainId: 6666665, walletAddress: rpc.address,
            contractAddress: rpc.address, predictedContractAddress: nil,
            creatorAddress: rpc.address, currentOwnerAddress: rpc.address, contractType: .standard,
            name: "Collection", symbol: "NFT", baseURI: legacy, maxSupply: "100", mintPrice: "3",
            deployTransactionHash: nil, transactionStatus: .confirmed, validationStatus: "manual", createdAt: Date()
        )
        let model = SRC721ContractDetailViewModel(
            record: record, service: rpc.service(), storage: SRC721Storage(defaults: defaults)
        )
        await model.refresh()?.value
        XCTAssertTrue(model.canManage)
        XCTAssertEqual(model.contractState?.baseURI, legacy)
        let reads = rpc.requestCount

        // An invalid supply prevents submission while exercising the real edit form.
        // An unchanged legacy URI must not become the form's first error.
        model.updateAll(
            baseURI: legacy, maxSupply: "invalid", mintPrice: "3",
            orgName: "Changed issuer", description: "Description", officialURL: "https://example.com",
            whitePaperURL: "https://example.com/paper", logo: nil
        )
        XCTAssertEqual(model.invalidField, .maxSupply)

        model.updateAll(
            baseURI: "ftp://example.com/new/", maxSupply: "100", mintPrice: "3",
            orgName: "Changed issuer", description: "Description", officialURL: "https://example.com",
            whitePaperURL: "https://example.com/paper", logo: nil
        )
        XCTAssertEqual(model.invalidField, .baseURI)
        XCTAssertEqual(rpc.requestCount, reads, "Validation must not submit or read any transaction")
    }

    func testMissingMintedTotalRemainsOptional() async throws {
        for type in [SRC721ContractType.standard, .burnable] {
            let rpc = SRC721ReadRPC(failingMethod: "mintedTotal()")
            defer { rpc.close() }

            let supply = try await rpc.service().supplyState(type: type)
            let detail = try await rpc.service().state(type: type)

            XCTAssertEqual(supply.totalSupply, 7)
            XCTAssertNil(supply.burnedCount)
            XCTAssertEqual(detail.totalSupply, 7)
            XCTAssertNil(detail.burnedCount)
            XCTAssertEqual(rpc.maximumInFlight, 1)
        }
    }

    func testRequiredReadFailureIsPropagated() async {
        let rpc = SRC721ReadRPC(failingMethod: "totalSupply()")
        defer { rpc.close() }
        do {
            _ = try await rpc.service().supplyState(type: .standard)
            XCTFail("A required read failure must not produce a supply snapshot")
        } catch {
            XCTAssertEqual(rpc.maximumInFlight, 1)
            XCTAssertEqual(rpc.requestCount, 1)
        }
    }
}

@MainActor
final class SRC721ManagerRefreshTests: XCTestCase {
    func testCachedCatalogIsShownImmediatelyOnReentryDuringSlowNetwork() async {
        let rpc = SRC721ReadRPC()
        defer { rpc.close() }
        let insight = SRC721RefreshInsight()
        insight.tokenResults = catalogTokens(creator: rpc.address, indices: 3...6)
        let first = makeModel(rpc: rpc, insight: insight, contractCount: 2)
        XCTAssertEqual(first.records.count, 2)
        XCTAssertEqual(insight.requestCount, 0, "Constructing an unused view model must not start requests")
        await waitForRefresh(first)
        XCTAssertEqual(first.records.count, 6)

        insight.stalls = true
        rpc.stalls = true
        let second = SRC721ManagerViewModel(
            service: rpc.service(insightProvider: insight), storage: first.storage,
            accountId: "test", walletAddress: rpc.address, refreshTimeoutNanoseconds: 500_000_000
        )
        XCTAssertEqual(second.records.count, 6, "Previously discovered rows must be visible before any network response")
        XCTAssertEqual(insight.requestCount, 1)
        await waitForRefresh(second)
        XCTAssertEqual(second.records.count, 6, "A failed refresh must retain the complete last-known list")
        XCTAssertFalse(second.isRefreshing)
        XCTAssertTrue(second.loadingContractAddresses.isEmpty)
    }

    func testSuccessfulCatalogReplacementPreservesLocalContractsAndHiddenRows() async {
        let rpc = SRC721ReadRPC()
        defer { rpc.close() }
        let insight = SRC721RefreshInsight()
        insight.tokenResults = catalogTokens(creator: rpc.address, indices: 1...4)
        let model = makeModel(rpc: rpc, insight: insight, contractCount: 2)
        await waitForRefresh(model)
        XCTAssertEqual(model.records.count, 4)
        XCTAssertEqual(model.records.first?.name, "Collection", "Local metadata takes precedence over the cached catalog")
        let hidden = model.records.first { $0.contractAddress.lowercased() == String(format: "0x%040x", 4) }!
        model.storage.hide(contract: hidden)
        model.reload()
        XCTAssertEqual(model.records.count, 3)
        await waitForRefresh(model)
        XCTAssertEqual(model.records.count, 3, "Refreshing the catalog must not resurrect hidden contracts")

        insight.tokenResults = []
        await waitForRefresh(model)
        XCTAssertEqual(model.records.count, 2, "A successful empty catalog replaces stale discoveries, preserving local records")
        XCTAssertTrue(model.storage.discoveredContracts(accountId: "test", chainId: 6666665, walletAddress: rpc.address).isEmpty)
    }

    func testCatalogSnapshotIsIsolatedByAccountChainAndWallet() async {
        let rpc = SRC721ReadRPC()
        defer { rpc.close() }
        let insight = SRC721RefreshInsight()
        insight.tokenResults = catalogTokens(creator: rpc.address, indices: 3...4)
        let model = makeModel(rpc: rpc, insight: insight, contractCount: 0)
        await waitForRefresh(model)
        let storage = model.storage
        XCTAssertEqual(storage.discoveredContracts(accountId: "test", chainId: 6666665, walletAddress: rpc.address.uppercased()).count, 2)
        XCTAssertTrue(storage.discoveredContracts(accountId: "another-account", chainId: 6666665, walletAddress: rpc.address).isEmpty)
        XCTAssertTrue(storage.discoveredContracts(accountId: "test", chainId: 6666666, walletAddress: rpc.address).isEmpty)
        XCTAssertTrue(storage.discoveredContracts(accountId: "test", chainId: 6666665, walletAddress: String(format: "0x%040x", 2)).isEmpty)
        XCTAssertTrue(storage.contracts(accountId: "test", chainId: 6666665, walletAddress: rpc.address).isEmpty,
                      "Indexer snapshots must not be promoted to locally deployed/imported contracts")
        storage.saveDiscoveredContracts([], accountId: "another-account", chainId: 6666665, walletAddress: rpc.address)
        XCTAssertEqual(storage.discoveredContracts(accountId: "test", chainId: 6666665, walletAddress: rpc.address).count, 2)
    }

    private func catalogTokens(creator: String, indices: ClosedRange<Int>) -> [SRC721InsightToken] {
        indices.map {
            SRC721InsightToken(address: String(format: "0x%040x", $0), name: "Remote collection", symbol: "NFT",
                               type: "erc721", logoURI: nil, template: true, creator: creator, burnable: false)
        }
    }

    func testCancelledWaiterFinishesWhileAnotherRequestStillOwnsSlot() async throws {
        let limiter = SRC721AsyncRequestLimiter(maximumConcurrentRequests: 1)
        try await limiter.acquire()
        let completion = expectation(description: "Queued cancellation must not wait for the active request")
        let queued = Task {
            do {
                try await limiter.acquire()
                XCTFail("The occupied slot must not be granted")
                await limiter.release()
            } catch {
                XCTAssertTrue(error is CancellationError)
            }
            completion.fulfill()
        }
        // Give the request an opportunity to join the wait queue before cancelling.
        try await Task.sleep(nanoseconds: 20_000_000)
        queued.cancel()
        await fulfillment(of: [completion], timeout: 1)
        await limiter.release()

        // Cancellation must not consume or leak the slot.
        let retry = expectation(description: "Slot remains usable")
        Task {
            try await limiter.acquire()
            await limiter.release()
            retry.fulfill()
        }
        await fulfillment(of: [retry], timeout: 1)
    }

    func testSuccessfulRefreshCoalescesAndLoadsSupply() async {
        let rpc = SRC721ReadRPC()
        defer { rpc.close() }
        let insight = SRC721RefreshInsight()
        let model = makeModel(rpc: rpc, insight: insight, contractCount: 1)
        async let first: Void = model.refreshAndWait()
        async let second: Void = model.refreshAndWait()
        _ = await (first, second)

        XCTAssertFalse(model.isRefreshing)
        XCTAssertTrue(model.loadingContractAddresses.isEmpty)
        XCTAssertNil(model.loadError)
        XCTAssertEqual(model.contractStates[rpc.address]?.totalSupply, 7)
        XCTAssertEqual(insight.requestCount, 1)
        XCTAssertEqual(rpc.requestCount, 3)
    }

    func testCatalogTimeoutEndsRefreshAndAllowsRetry() async {
        let rpc = SRC721ReadRPC()
        defer { rpc.close() }
        let insight = SRC721RefreshInsight()
        insight.stalls = true
        let model = makeModel(rpc: rpc, insight: insight, contractCount: 1)
        await waitForRefresh(model)

        XCTAssertFalse(model.isRefreshing)
        XCTAssertEqual(model.loadError, URLError(.timedOut).localizedDescription)
        XCTAssertEqual(insight.cancellationCount, 1)
        // Successful RPC results survive an unrelated catalog timeout.
        XCTAssertEqual(model.contractStates[rpc.address]?.totalSupply, 7)

        insight.stalls = false
        await waitForRefresh(model)
        XCTAssertFalse(model.isRefreshing)
        XCTAssertNil(model.loadError)
        XCTAssertEqual(insight.requestCount, 2)
    }

    func testRPCTimeoutCancelsActiveAndQueuedRequestsAndAllowsRetry() async {
        let rpc = SRC721ReadRPC()
        defer { rpc.close() }
        let insight = SRC721RefreshInsight()
        let model = makeModel(rpc: rpc, insight: insight, contractCount: 6)
        await waitForRefresh(model)
        XCTAssertEqual(model.contractStates.count, 6)
        let completedRequests = rpc.requestCount

        rpc.stalls = true
        await waitForRefresh(model)
        XCTAssertFalse(model.isRefreshing)
        XCTAssertTrue(model.loadingContractAddresses.isEmpty)
        XCTAssertEqual(model.loadError, URLError(.timedOut).localizedDescription)
        XCTAssertEqual(model.contractStates.count, 6, "Keep the last successful snapshots")
        XCTAssertEqual(rpc.requestCount - completedRequests, 4, "Queued contracts must not start I/O after cancellation")
        XCTAssertEqual(rpc.cancelledRequestCount, 4)

        rpc.stalls = false
        await waitForRefresh(model)
        XCTAssertFalse(model.isRefreshing)
        XCTAssertTrue(model.loadingContractAddresses.isEmpty)
        XCTAssertNil(model.loadError)
        XCTAssertEqual(rpc.requestCount - completedRequests, 4 + 6 * 3)
        XCTAssertLessThanOrEqual(rpc.maximumInFlight, 4)
    }

    func testFailedRPCFinishesRefreshAndClearsRowLoading() async {
        let rpc = SRC721ReadRPC(failingMethod: "totalSupply()")
        defer { rpc.close() }
        let model = makeModel(rpc: rpc, insight: SRC721RefreshInsight(), contractCount: 1)
        await waitForRefresh(model)
        XCTAssertFalse(model.isRefreshing)
        XCTAssertTrue(model.loadingContractAddresses.isEmpty)
        XCTAssertNotNil(model.loadError)
        XCTAssertTrue(model.contractStates.isEmpty)
    }

    private func waitForRefresh(_ model: SRC721ManagerViewModel) async {
        let completion = expectation(description: "Refresh must finish")
        let waiter = Task {
            await model.refreshAndWait()
            completion.fulfill()
        }
        await fulfillment(of: [completion], timeout: 3)
        waiter.cancel()
    }

    private func makeModel(rpc: SRC721ReadRPC, insight: SRC721RefreshInsight, contractCount: Int) -> SRC721ManagerViewModel {
        let suite = "SRC721ManagerRefreshTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let storage = SRC721Storage(defaults: defaults)
        for index in 0..<contractCount {
            storage.save(contract: SRC721ContractRecord(
                accountId: "test", chainId: 6666665, walletAddress: rpc.address,
                contractAddress: String(format: "0x%040x", index + 1), predictedContractAddress: nil,
                creatorAddress: rpc.address, currentOwnerAddress: nil, contractType: .standard,
                name: "Collection", symbol: "NFT", baseURI: "ipfs://collection/", maxSupply: "100", mintPrice: "0",
                deployTransactionHash: nil, transactionStatus: .confirmed, validationStatus: "manual", createdAt: Date()
            ))
        }
        return SRC721ManagerViewModel(
            service: rpc.service(insightProvider: insight), storage: storage, accountId: "test", walletAddress: rpc.address,
            refreshTimeoutNanoseconds: 500_000_000
        )
    }
}

private final class SRC721RefreshInsight: SRC721InsightAssetProvider {
    var tokenResults: [SRC721InsightToken] = []
    var stalls = false
    private(set) var requestCount = 0
    private(set) var cancellationCount = 0

    @MainActor
    func tokens() async throws -> [SRC721InsightToken] {
        requestCount += 1
        if stalls {
            do {
                try await Task.sleep(nanoseconds: 60_000_000_000)
            } catch {
                cancellationCount += 1
                throw error
            }
        }
        return tokenResults
    }

    func holdings(owner: String) async throws -> [SRC721InsightHolding] { [] }
    func assets(owner: String, tokenAddress: String) async throws -> [SRC721InsightAsset] { [] }
}

private final class SRC721ReadRPC: Web3Provider {
    let address = "0x0000000000000000000000000000000000000001"
    var network: Networks? = .Custom(networkID: 6666665)
    var attachedKeystoreManager: KeystoreManager?
    var policies = Policies()
    let url = URL(string: "https://\(UUID().uuidString.lowercased()).invalid")!
    let session: URLSession

    private let lock = NSLock()
    private var inFlight = 0
    private var peakInFlight = 0
    private var requests = 0
    private var cancelledRequests = 0
    private var shouldStall = false

    var stalls: Bool {
        get { lock.withLock { shouldStall } }
        set { lock.withLock { shouldStall = newValue } }
    }
    var cancelledRequestCount: Int { lock.withLock { cancelledRequests } }
    private let results: [String: String]
    private let failingSelector: String?

    var maximumInFlight: Int { lock.withLock { peakInFlight } }
    var requestCount: Int { lock.withLock { requests } }

    init(failingMethod: String? = nil, baseURI: String = "ipfs://collection/") {
        failingSelector = failingMethod.map(Self.selector)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SRC721ReadURLProtocol.self]
        session = URLSession(configuration: configuration)
        let fields: [String: String] = [
            "name()": Self.dynamic(Data("Collection".utf8)),
            "symbol()": Self.dynamic(Data("NFT".utf8)),
            "owner()": Self.word(1),
            "baseURI()": Self.dynamic(Data(baseURI.utf8)),
            "maxSupply()": Self.word(100),
            "totalSupply()": Self.word(7),
            "remainSupply()": Self.word(91),
            "mintedTotal()": Self.word(9),
            "mintPrice()": Self.word(3),
            "orgName()": Self.dynamic(Data("Issuer".utf8)),
            "description()": Self.dynamic(Data("Description".utf8)),
            "officialUrl()": Self.dynamic(Data("https://example.com".utf8)),
            "whitePaperUrl()": Self.dynamic(Data("https://example.com/paper".utf8)),
            "logo()": Self.dynamic(Data([1, 2, 3])),
        ]
        results = Dictionary(uniqueKeysWithValues: fields.map { (Self.selector($0.key), "0x" + $0.value) })
        SRC721ReadURLProtocol.register(self)
    }

    func service(insightProvider: SRC721InsightAssetProvider? = nil) -> SRC721Service {
        SRC721Service(privateKey: Data(), userAddress: address, chainId: 6666665, contractAddress: address, insightProvider: insightProvider, web3Factory: {
            Web3(provider: self)
        })
    }

    func close() {
        session.invalidateAndCancel()
        SRC721ReadURLProtocol.unregister(self)
    }

    func begin(selector: String, id: Any) -> [String: Any] {
        lock.withLock {
            inFlight += 1
            peakInFlight = max(peakInFlight, inFlight)
            requests += 1
        }
        guard selector != failingSelector, let result = results[selector] else {
            return ["jsonrpc": "2.0", "id": id, "error": ["code": -32000, "message": "execution reverted"]]
        }
        return ["jsonrpc": "2.0", "id": id, "result": result]
    }

    func end(cancelled: Bool = false) {
        lock.withLock {
            inFlight -= 1
            if cancelled { cancelledRequests += 1 }
        }
    }

    private static func selector(_ method: String) -> String {
        "0x" + Data(method.utf8).sha3(.keccak256).prefix(4).toHexString()
    }

    private static func word(_ value: Int) -> String {
        let hex = String(value, radix: 16)
        return String(repeating: "0", count: 64 - hex.count) + hex
    }

    private static func dynamic(_ value: Data) -> String {
        let hex = value.toHexString()
        return word(32) + word(value.count) + hex + String(repeating: "0", count: (64 - hex.count % 64) % 64)
    }
}

private final class SRC721ReadURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var fixtures: [String: SRC721ReadRPC] = [:]

    static func register(_ rpc: SRC721ReadRPC) {
        lock.withLock { fixtures[rpc.url.host!] = rpc }
    }

    static func unregister(_ rpc: SRC721ReadRPC) {
        _ = lock.withLock { fixtures.removeValue(forKey: rpc.url.host!) }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    private let completionLock = NSLock()
    private var activeRPC: SRC721ReadRPC?

    override func stopLoading() {
        completionLock.withLock {
            activeRPC?.end(cancelled: true)
            activeRPC = nil
        }
    }

    override func startLoading() {
        do {
            guard let host = request.url?.host,
                  let rpc = Self.lock.withLock({ Self.fixtures[host] }) else { throw URLError(.unsupportedURL) }
            var body = request.httpBody ?? Data()
            if body.isEmpty, let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
                    if count == 0 { break }
                    body.append(contentsOf: buffer.prefix(count))
                }
            }
            guard let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
                  json["method"] as? String == "eth_call",
                  let params = json["params"] as? [Any],
                  let transaction = params.first as? [String: Any],
                  let input = (transaction["data"] ?? transaction["input"]) as? String else {
                throw URLError(.cannotParseResponse)
            }
            let response = rpc.begin(selector: String(input.prefix(10)), id: json["id"] ?? 1)
            completionLock.withLock { activeRPC = rpc }
            if rpc.stalls { return } // URLSession cancellation must still finish the awaiting task.
            let data = try JSONSerialization.data(withJSONObject: response)
            // Keep the request in flight long enough to expose concurrent sibling reads.
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.02) {
                let shouldComplete = self.completionLock.withLock { () -> Bool in
                    guard let active = self.activeRPC else { return false }
                    active.end()
                    self.activeRPC = nil
                    return true
                }
                guard shouldComplete else { return }
                let http = HTTPURLResponse(url: self.request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                self.client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: data)
                self.client?.urlProtocolDidFinishLoading(self)
            }
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}
