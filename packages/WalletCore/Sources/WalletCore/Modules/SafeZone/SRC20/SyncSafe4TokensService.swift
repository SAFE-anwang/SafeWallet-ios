import Foundation
import Combine
import RxSwift
import RxCocoa
import RxRelay
import MarketKit
import EvmKit

class SyncSafe4TokensService {
    private let userDefaultsStorage = Core.shared.userDefaultsStorage
    private let accountManager = Core.shared.accountManager
    private let walletManager = Core.shared.walletManager
    private var disposeBag = DisposeBag()
    private let storage: Safe4CustomTokenStorage
    private let provider: SyncSafe4TokensProvider
    private let srC20Service: SRC20Service
    private let evmKit: EvmKit.Kit
    private let marketKit: MarketKit.Kit
    private let src20ProjectionCoordinator = Core.shared.safe4SRC20ProjectionCoordinator
    private let taskStateQueue = DispatchQueue(label: "\(AppConfig.label).sync_safe4_tokens")
    private let dataRelay: BehaviorRelay<[Safe4CustomTokenRecord]>
    private var isSyncing = false
    private var refreshAfterCurrentSync = false
    private var requestTask: Task<Void, Never>?
    private var versionTask: Task<Void, Never>?
    private var activeRequestId: UUID?
    private var activeVersionId: UUID?
    private let ownerAccountId: String?
    private let ownerChildWalletId: String?
    private let ownerAddress: String
    private let chainId: Int

    private let versionRequestConcurrencyLimit = 4

    private func diagnosticLog(_ message: @autoclosure () -> String) {
        let thread = Thread.isMainThread ? "main" : (Thread.current.name ?? "background")
        print("[SyncSafe4TokensService] [\(thread)] [chain=\(chainId)] \(Date()) \(message())")
    }

    init(provider: SyncSafe4TokensProvider, srC20Service: SRC20Service, evmKit: EvmKit.Kit, storage: Safe4CustomTokenStorage, marketKit: MarketKit.Kit, chainId: Int = Safe4Network.currentChainId) {
        self.provider = provider
        self.srC20Service = srC20Service
        self.evmKit = evmKit
        self.storage = storage
        self.marketKit = marketKit
        self.chainId = chainId
        let activeAccount = Core.shared.accountManager.activeAccount
        ownerAccountId = activeAccount?.id
        ownerChildWalletId = activeAccount.flatMap { ChildWalletBridge.shared.activeChildWalletId(account: $0) }
        let ownerAddress = evmKit.receiveAddress.eip55.lowercased()
        self.ownerAddress = ownerAddress
        let initialOwnedTokens = storage.allTokens(chainId: chainId)
            .filter { $0.creator.lowercased() == ownerAddress }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        dataRelay = BehaviorRelay(value: initialOwnedTokens)
    }

    func requestTokens(forceRefresh: Bool = false) {
        let requestId = UUID()
        taskStateQueue.async {
            self.diagnosticLog("request begin id=\(requestId) isSyncing=\(self.isSyncing) hasRequestTask=\(self.requestTask != nil)")
            guard !self.isSyncing else {
                if forceRefresh {
                    self.refreshAfterCurrentSync = true
                }
                self.diagnosticLog("request skipped id=\(requestId) reason=already-syncing")
                return
            }

            self.isSyncing = true
            self.activeRequestId = requestId
            let provider = self.provider
            let task = Task { [self, provider] in
                defer {
                    self.taskStateQueue.async { [self] in
                        guard self.activeRequestId == requestId else { return }
                        self.isSyncing = false
                        self.requestTask = nil
                        self.activeRequestId = nil
                        self.diagnosticLog("request task finished id=\(requestId)")
                        if self.refreshAfterCurrentSync {
                            self.refreshAfterCurrentSync = false
                            self.requestTokens()
                        }
                    }
                }

                do {
                    let data = try await provider.requestTokens()
                    diagnosticLog("request provider success id=\(requestId) tokens=\(data.tokens.count) cancelled=\(Task.isCancelled)")
                    try Task.checkCancellation()
                    await processIfCurrent(data: data, requestId: requestId)
                    diagnosticLog("request process finished id=\(requestId)")
                } catch {
                    diagnosticLog("request failed id=\(requestId) cancelled=\(Task.isCancelled) error=\(error)")
                }
            }
            self.requestTask = task
            self.diagnosticLog("request scheduled id=\(requestId)")
        }
    }

    private func processIfCurrent(data: Safe4TokensResponse, requestId: UUID) async {
        await withCheckedContinuation { continuation in
            taskStateQueue.async { [self] in
                guard self.activeRequestId == requestId else {
                    continuation.resume()
                    return
                }

                guard self.isCurrentOwnerContext() else {
                    self.diagnosticLog("response discarded for stale wallet context requestId=\(requestId)")
                    continuation.resume()
                    return
                }

                self.process(data: data)
                continuation.resume()
            }
        }
    }

    private func process(data: Safe4TokensResponse) {
        diagnosticLog("process begin tokens=\(data.tokens.count)")

        guard data.tokens.allSatisfy({ $0.chainId == chainId }) else {
            diagnosticLog("response discarded: token chainId does not match sync chain")
            return
        }

        guard !data.tokens.isEmpty else {
            diagnosticLog("response discarded: empty token snapshot")
            return
        }

        for token in data.tokens {
            // The API uses a non-empty logo as the promotion marker. Keep this independent
            // of the active owner so the cached directory can be filtered for any account.
            token.isPromoted = token.logoURI?.isEmpty == false
        }

        let userTokens = data.tokens.filter { $0.creator.lowercased() == ownerAddress }
        let ownedTokens = uniqueTokens(promotedTokens: [], ownedTokens: userTokens)
        // Persist the complete API directory so unpromoted contracts can be rejected
        // consistently by local and MarketKit-backed search paths. Owner metadata wins
        // if the API returns the same address more than once.
        let allTokens = uniqueTokens(
            promotedTokens: data.tokens.filter { $0.creator.lowercased() != ownerAddress },
            ownedTokens: userTokens
        )
        let tokensToSync = allTokens.filter { $0.isEligible(forOwner: ownerAddress) }
        let ownedAddresses = Set(ownedTokens.map { $0.address.lowercased() })

        do {
            try storage.synchronize(
                tokens: allTokens,
                ownedBy: ownerAddress,
                ownedAddresses: ownedAddresses,
                chainId: chainId
            )
        } catch {
            diagnosticLog("storage synchronization failed error=\(error)")
            return
        }

        data.tokens.forEach { saveLogo(tokenInfo: $0) }

        // This cache is consumed by the chain's transaction decorator, so it must contain
        // all deployed contracts on the chain, not only contracts created by this wallet.
        let nativeContractAddress = "0x0000000000000000000000000000000000001101"
        let deployContracts = data.tokens
            .map { $0.address.lowercased() }
            .filter { $0 != nativeContractAddress }
        userDefaultsStorage.set(value: deployContracts, for: Safe4Network.deployContractsKey(chainId: chainId))
        if Safe4Network.isCurrent(chainId: chainId) {
            userDefaultsStorage.set(value: deployContracts, for: Safe4CustomTokenManager.safe4DeployContractsKey)
        }

        syncMarketTokens(tokensToSync)

        src20ProjectionCoordinator.reconcileCurrentChain(chainId: chainId)

        versionTask?.cancel()
        let versionId = UUID()
        activeVersionId = versionId
        let task = Task { [self] in
            diagnosticLog("version task entered id=\(versionId) tokens=\(ownedTokens.count)")
            do {
                let results = await requestVersion(tokens: ownedTokens)
                try Task.checkCancellation()

                taskStateQueue.async { [self] in
                    guard self.activeVersionId == versionId else { return }
                    if self.isCurrentOwnerContext() {
                        do {
                            let versions = Dictionary(results.compactMap { token in
                                token.version.flatMap { $0.isEmpty ? nil : (token.address, $0) }
                            }, uniquingKeysWith: { _, latest in latest })
                            try self.storage.updateVersions(versions, chainId: self.chainId)
                        } catch {
                            self.diagnosticLog("batch token version update failed error=\(error)")
                        }
                        self.dataRelay.accept(results.sorted { lhsItem, rhsItem in
                            lhsItem.name.caseInsensitiveCompare(rhsItem.name) == .orderedAscending
                        })
                    } else {
                        self.diagnosticLog("version result discarded for stale wallet context versionId=\(versionId)")
                    }
                    self.activeVersionId = nil
                    self.versionTask = nil
                    self.diagnosticLog("version task finished id=\(versionId) results=\(results.count)")
                }
            } catch {
                let cancelled = Task.isCancelled
                taskStateQueue.async { [self] in
                    guard self.activeVersionId == versionId else { return }
                    self.activeVersionId = nil
                    self.versionTask = nil
                    self.diagnosticLog("version task failed id=\(versionId) cancelled=\(cancelled) error=\(error)")
                }
            }
        }
        versionTask = task
        diagnosticLog("process end versionId=\(versionId)")
    }

    private func uniqueTokens(promotedTokens: [Safe4CustomTokenRecord], ownedTokens: [Safe4CustomTokenRecord]) -> [Safe4CustomTokenRecord] {
        var orderedAddresses = [String]()
        var tokensByAddress = [String: Safe4CustomTokenRecord]()

        for token in promotedTokens + ownedTokens {
            let address = token.address.lowercased()
            if tokensByAddress[address] == nil {
                orderedAddresses.append(address)
            }
            // If a response contains the same contract twice, owner metadata takes precedence.
            tokensByAddress[address] = token
        }

        return orderedAddresses.compactMap { tokensByAddress[$0] }
    }

    private func syncMarketTokens(_ tokens: [Safe4CustomTokenRecord]) {
        guard !tokens.isEmpty else { return }

        let tokenQueries = tokens.map {
            TokenQuery(blockchainType: .safe4, tokenType: .eip20(address: $0.address))
        }
        var resolvedTokenIds = Set<String>()
        var failedLookupTokenIds = Set<String>()

        for (tokenChunk, queryChunk) in zip(tokens.chunks(500), tokenQueries.chunks(500)) {
            do {
                let marketTokens = try marketKit.tokens(queries: queryChunk)
                resolvedTokenIds.formUnion(marketTokens.map { $0.tokenQuery.id.lowercased() })
            } catch {
                diagnosticLog("batch MarketKit lookup failed; falling back for chunk size=\(queryChunk.count) error=\(error)")
                for (token, query) in zip(tokenChunk, queryChunk) {
                    do {
                        if try marketKit.token(query: query) != nil {
                            resolvedTokenIds.insert(query.id.lowercased())
                        }
                    } catch {
                        failedLookupTokenIds.insert(query.id.lowercased())
                        diagnosticLog("MarketKit token lookup failed address=\(token.address) error=\(error)")
                    }
                }
            }
        }

        for (token, query) in zip(tokens, tokenQueries)
        where !resolvedTokenIds.contains(query.id.lowercased())
            && !failedLookupTokenIds.contains(query.id.lowercased()) {
            if insertMarketToken(token) {
                resolvedTokenIds.insert(query.id.lowercased())
            }
        }

        reloadWalletsIfNeeded(tokens: tokens, resolvedTokenIds: resolvedTokenIds)
    }

    private func insertMarketToken(_ tokenInfo: Safe4CustomTokenRecord) -> Bool {
        let tokenQuery = TokenQuery(blockchainType: .safe4, tokenType: .eip20(address: tokenInfo.address))
        do {
            let coin = Coin(uid: tokenQuery.customCoinUid, name: tokenInfo.name, code: tokenInfo.symbol)
            // A previous partial sync may have inserted the coin but not its token.
            // Treat an existing coin as reusable and make the token insertion idempotent.
            try? marketKit.insertCoin(coin: coin)
            try marketKit.insertToken(
                coinUid: tokenQuery.customCoinUid,
                blockchainUid: BlockchainType.safe4.uid,
                type: "eip20",
                decimals: tokenInfo.decimals,
                reference: tokenInfo.address
            )
            return true
        } catch {
            diagnosticLog("MarketKit token insert failed address=\(tokenInfo.address) error=\(error)")
            return false
        }
    }

    private func reloadWalletsIfNeeded(tokens: [Safe4CustomTokenRecord], resolvedTokenIds: Set<String>) {
        guard canReloadActiveWallets() else { return }

        let activeWalletTokenIds = Set(walletManager.activeWalletData.wallets.map { $0.token.tokenQuery.id.lowercased() })
        let hasNewActiveWalletToken = tokens.contains { token in
            let tokenId = TokenQuery(blockchainType: .safe4, tokenType: .eip20(address: token.address)).id.lowercased()
            return resolvedTokenIds.contains(tokenId) && !activeWalletTokenIds.contains(tokenId)
        }

        if hasNewActiveWalletToken {
            walletManager.preloadWallets()
        }
    }

    private func requestVersion(tokens: [Safe4CustomTokenRecord]) async -> [Safe4CustomTokenRecord] {
        guard !tokens.isEmpty else { return [] }

        var iterator = tokens.makeIterator()
        return await withTaskGroup(of: Safe4CustomTokenRecord.self) { taskGroup in
            for _ in 0..<min(versionRequestConcurrencyLimit, tokens.count) {
                if let token = iterator.next() {
                    taskGroup.addTask { [self] in await resolveVersion(for: token) }
                }
            }

            var results = [Safe4CustomTokenRecord]()
            while let token = await taskGroup.next() {
                results.append(token)
                if let nextToken = iterator.next() {
                    taskGroup.addTask { [self] in await resolveVersion(for: nextToken) }
                }
            }
            return results
        }
    }

    private func resolveVersion(for token: Safe4CustomTokenRecord) async -> Safe4CustomTokenRecord {
        do {
            try Task.checkCancellation()
            if let version = token.version, !version.isEmpty {
                return token
            }

            if let storedVersion = try storage.asset(address: token.address, chainId: chainId)?.version,
               !storedVersion.isEmpty {
               token.version = storedVersion
                return token
            }

            let version = try await srC20Service.version(chainId: chainId, contract: token.address)
            try Task.checkCancellation()
            token.version = version
        } catch {
            diagnosticLog("token version lookup failed address=\(token.address) error=\(error)")
        }

        return token
    }

    private func canReloadActiveWallets() -> Bool {
        guard isCurrentOwnerContext() else {
            return false
        }

        let activeWalletData = walletManager.activeWalletData
        guard activeWalletData.account?.id == ownerAccountId,
              activeWalletData.childWalletId == ownerChildWalletId
        else {
            return false
        }

        return activeWalletData.wallets.contains { wallet in
            wallet.account.id == ownerAccountId && wallet.token.isSafe4Native
        }
    }

    private func isCurrentOwnerContext() -> Bool {
        guard Safe4Network.isCurrent(chainId: chainId),
              let activeAccount = accountManager.activeAccount,
              activeAccount.id == ownerAccountId
        else {
            return false
        }

        return ChildWalletBridge.shared.activeChildWalletId(account: activeAccount) == ownerChildWalletId
    }

    private func saveLogo(tokenInfo: Safe4CustomTokenRecord) {
        let tokenQuery = TokenQuery(blockchainType: .safe4, tokenType: .eip20(address: tokenInfo.address))
        if let url = tokenInfo.logoURI {
            userDefaultsStorage.set(value: url, for: Safe4Network.logoKey(coinUid: tokenQuery.customCoinUid, chainId: chainId))
            if Safe4Network.isCurrent(chainId: chainId) {
                userDefaultsStorage.set(value: url, for: tokenQuery.customCoinUid.lowercased())
            }
        }
    }

    func logo(coinUid: String) -> String? {
        userDefaultsStorage.value(for: Safe4Network.logoKey(coinUid: coinUid, chainId: chainId)) ?? userDefaultsStorage.value(for: coinUid.lowercased())
    }

    func cancel() {
        taskStateQueue.sync {
            diagnosticLog("cancel begin isSyncing=\(isSyncing) hasRequestTask=\(requestTask != nil) hasVersionTask=\(versionTask != nil)")
            activeRequestId = nil
            activeVersionId = nil
            refreshAfterCurrentSync = false
            requestTask?.cancel()
            versionTask?.cancel()
            requestTask = nil
            versionTask = nil
            isSyncing = false
            diagnosticLog("cancel end")
        }
    }

    func isServingCurrentContext(chainId: Int) -> Bool {
        self.chainId == chainId && isCurrentOwnerContext()
    }

    var dataDriver: Observable<[Safe4CustomTokenRecord]> {
        dataRelay.asObservable()
    }

}
