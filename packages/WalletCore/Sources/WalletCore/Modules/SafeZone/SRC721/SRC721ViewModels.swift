import BigInt
import Combine
import Foundation
import UIKit
import Web3Core

enum SRC721DeployField: Hashable {
    case name, symbol, baseURI, maxSupply, mintPrice
}

enum SRC721ImportField: Hashable {
    case address
}

enum SRC721DetailField: Hashable {
    case mintRecipient, mintAmount
    case baseURI, maxSupply, mintPrice, orgName, description, officialURL, whitePaperURL, logo
    case tokenId, tokenRecipient, operatorAddress
}

@MainActor
final class SRC721DeployViewModel: ObservableObject {
    private let service: SRC721Service
    private let storage: SRC721Storage
    private let accountId: String
    private let walletAddress: String

    @Published var type: SRC721ContractType = .standard
    @Published var name = ""
    @Published var symbol = ""
    @Published var baseURI = ""
    @Published var maxSupply = ""
    @Published var mintPrice = "0"
    @Published var sendState: SRC721AsyncState = .idle
    @Published private(set) var submissionID = UUID()
    @Published var errorMessage: String?
    @Published var nameCautionState: CautionState = .none
    @Published var symbolCautionState: CautionState = .none
    @Published var baseURICautionState: CautionState = .none
    @Published var maxSupplyCautionState: CautionState = .none
    @Published var mintPriceCautionState: CautionState = .none
    @Published private(set) var invalidField: SRC721DeployField?
    @Published private(set) var validationRequestID = UUID()

    init(service: SRC721Service, storage: SRC721Storage, accountId: String, walletAddress: String) {
        self.service = service
        self.storage = storage
        self.accountId = accountId
        self.walletAddress = walletAddress
    }

    @MainActor
    func validateForSubmit() -> Bool {
        clearCautions()
        var isValid = true

        do {
            _ = try SRC721Validation.required(name, field: "safe_zone.src721.field.name".localized, maxLength: SRC721Validation.nameMaxUTF8Length)
        } catch {
            setCaution(error.localizedDescription, for: .name)
            isValid = false
        }

        do {
            _ = try SRC721Validation.required(symbol, field: "safe_zone.src721.field.symbol".localized, maxLength: SRC721Validation.symbolMaxUTF8Length)
        } catch {
            setCaution(error.localizedDescription, for: .symbol)
            isValid = false
        }

        do {
            _ = try SRC721Validation.optionalBaseURI(baseURI)
        } catch {
            setCaution(error.localizedDescription, for: .baseURI)
            isValid = false
        }

        do {
            _ = try SRC721Validation.amount(maxSupply, field: "safe_zone.src721.field.max_supply".localized)
        } catch {
            setCaution(error.localizedDescription, for: .maxSupply)
            isValid = false
        }

        do {
            _ = try SRC721Validation.safe4Amount(mintPrice, field: "safe_zone.src721.field.mint_price".localized, allowZero: true)
        } catch {
            setCaution(error.localizedDescription, for: .mintPrice)
            isValid = false
        }

        return isValid
    }

    func deploy() {
        guard sendState != .sending, validateForSubmit() else { return }
        sendState = .sending
        errorMessage = nil
        Task { [weak self] in
            guard let self else { return }
            var draft: SRC721ContractRecord?
            var hasBroadcast = false
            do {
                let name = try SRC721Validation.required(name, field: "safe_zone.src721.field.name".localized, maxLength: SRC721Validation.nameMaxUTF8Length)
                let symbol = try SRC721Validation.required(symbol, field: "safe_zone.src721.field.symbol".localized, maxLength: SRC721Validation.symbolMaxUTF8Length)
                let baseURI = try SRC721Validation.optionalBaseURI(baseURI)
                let maxSupply = try SRC721Validation.amount(maxSupply, field: "safe_zone.src721.field.max_supply".localized)
                let mintPrice = try SRC721Validation.safe4Amount(mintPrice, field: "safe_zone.src721.field.mint_price".localized, allowZero: true)
                let predictedAddress = try await service.predictedDeploymentAddress()
                let draftRecord = SRC721ContractRecord(
                    accountId: accountId,
                    chainId: service.chainId,
                    walletAddress: walletAddress,
                    contractAddress: predictedAddress,
                    predictedContractAddress: predictedAddress,
                    creatorAddress: walletAddress,
                    currentOwnerAddress: walletAddress,
                    contractType: type,
                    name: name,
                    symbol: symbol,
                    baseURI: baseURI,
                    maxSupply: maxSupply.description,
                    mintPrice: mintPrice.description,
                    deployTransactionHash: nil,
                    transactionStatus: .pending,
                    validationStatus: "deployed",
                    createdAt: Date()
                )
                draft = draftRecord
                storage.save(contract: draftRecord)
                let deployment = try await service.deploy(type: type, name: name, symbol: symbol, baseURI: baseURI, maxSupply: maxSupply, mintPrice: mintPrice) { hash in
                    hasBroadcast = true
                    var submitted = draftRecord
                    submitted.deployTransactionHash = hash
                    self.storage.update(contract: submitted)
                    self.submissionID = UUID()
                }
                storage.remove(contract: draftRecord)
                let record = SRC721ContractRecord(
                    accountId: accountId,
                    chainId: service.chainId,
                    walletAddress: walletAddress,
                    contractAddress: deployment.contractAddress,
                    predictedContractAddress: predictedAddress,
                    creatorAddress: walletAddress,
                    currentOwnerAddress: walletAddress,
                    contractType: type,
                    name: name,
                    symbol: symbol,
                    baseURI: baseURI,
                    maxSupply: maxSupply.description,
                    mintPrice: mintPrice.description,
                    deployTransactionHash: deployment.transactionHash,
                    transactionStatus: .pending,
                    validationStatus: "deployed",
                    createdAt: draftRecord.createdAt
                )
                storage.save(contract: record)
                let success = try await service.waitForTransaction(deployment.transactionHash)
                var updated = record
                updated.transactionStatus = success ? .confirmed : .failed
                if success, let deployedAddress = try? await service.deployedContractAddress(for: deployment.transactionHash) {
                    updated.contractAddress = deployedAddress
                }
                storage.update(contract: updated)
                await MainActor.run {
                    self.sendState = success ? .completed : .failed
                    self.errorMessage = success ? nil : "safe_zone.src721.error.transaction".localized
                }
            } catch {
                if let draft, !hasBroadcast { storage.remove(contract: draft) }
                await MainActor.run {
                    self.sendState = .failed
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private enum DeployField {
        case name, symbol, baseURI, maxSupply, mintPrice
    }

    private func clearCautions() {
        invalidField = nil
        nameCautionState = .none
        symbolCautionState = .none
        baseURICautionState = .none
        maxSupplyCautionState = .none
        mintPriceCautionState = .none
    }

    private func setCaution(_ message: String, for field: DeployField) {
        let caution = CautionState.caution(Caution(text: message, type: .error))
        let invalidField: SRC721DeployField
        switch field {
        case .name:
            nameCautionState = caution
            invalidField = .name
        case .symbol:
            symbolCautionState = caution
            invalidField = .symbol
        case .baseURI:
            baseURICautionState = caution
            invalidField = .baseURI
        case .maxSupply:
            maxSupplyCautionState = caution
            invalidField = .maxSupply
        case .mintPrice:
            mintPriceCautionState = caution
            invalidField = .mintPrice
        }
        if self.invalidField == nil {
            self.invalidField = invalidField
            validationRequestID = UUID()
        }
    }

}

@MainActor
final class SRC721ManagerViewModel: ObservableObject {
    private static let maximumConcurrentContractStateRequests = 4
    private static let maximumConcurrentReceiptRequests = 4

    let service: SRC721Service
    let storage: SRC721Storage
    let accountId: String
    let walletAddress: String

    @Published private(set) var records: [SRC721ContractRecord] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var loadError: String?
    @Published private(set) var pendingTokenContractAddresses = Set<String>()
    @Published private(set) var contractStates: [String: SRC721ContractSupplyState] = [:]
    @Published private(set) var loadingContractAddresses = Set<String>()
    private var discoveredRecords: [SRC721ContractRecord] = []
    private var transactionSnapshot: [SRC721TransactionRecord] = []
    private var pendingMintContractAddresses = Set<String>()
    private var pendingMintAmountsByContract: [String: BigUInt] = [:]
    private var contractStateRequestIDs: [String: UUID] = [:]
    private var contractStateRequests: [String: (id: UUID, task: Task<SRC721ContractStateResponse, Never>)] = [:]
    private var isResolvingPendingTransactions = false
    private var refreshTask: Task<Void, Never>?
    private let contractStateRequestLimiter = SRC721AsyncRequestLimiter(maximumConcurrentRequests: maximumConcurrentContractStateRequests)

    init(service: SRC721Service, storage: SRC721Storage, accountId: String, walletAddress: String) {
        self.service = service
        self.storage = storage
        self.accountId = accountId
        self.walletAddress = walletAddress
        reload()
        Task { await refreshAndWait() }
    }

    func reload() {
        let localRecords = storage.contracts(accountId: accountId, chainId: service.chainId, walletAddress: walletAddress)
        records = SRC721ContractRecord.merging(localRecords: localRecords, discoveredRecords: discoveredRecords)
            .filter { !storage.isHidden(contract: $0) }
        transactionSnapshot = storage.transactions(accountId: accountId, chainId: service.chainId, walletAddress: walletAddress)
        let pendingTransactions = transactionSnapshot.filter { $0.status == .pending }
        pendingTokenContractAddresses = Set(pendingTransactions.compactMap { transaction in
            guard transaction.tokenOperation != nil else { return nil }
            return Web3Core.EthereumAddress(transaction.contractAddress)?.address.lowercased()
        })
        let pendingMints = pendingTransactions.filter { $0.operationKind == .mint }
        pendingMintContractAddresses = Set(pendingMints.compactMap {
            Web3Core.EthereumAddress($0.contractAddress)?.address.lowercased()
        })
        pendingMintAmountsByContract = pendingMints.reduce(into: [:]) { result, transaction in
            guard let address = Web3Core.EthereumAddress(transaction.contractAddress)?.address.lowercased(),
                  let amount = transaction.amount.flatMap(BigUInt.init) else { return }
            result[address, default: .zero] += amount
        }
    }

    func refresh() {
        Task { await refreshAndWait() }
    }

    func refreshAndWait() async {
        if let refreshTask {
            await refreshTask.value
            return
        }

        reload()
        isRefreshing = true
        loadError = nil
        let task: Task<Void, Never> = Task { [weak self] in
            await self?.performRefresh()
        }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func performRefresh() async {
        defer { isRefreshing = false }

        schedulePendingTransactionResolution()
        let tokenRequest = Task { try await service.insightTokens() }

        // Known contracts can load immediately while the Insight catalog is fetched.
        let initialRecords = records
        let initiallyLoadedAddresses = Set(initialRecords.compactMap { record -> String? in
            guard record.transactionStatus == .confirmed, record.contractType != .unknown else { return nil }
            return record.contractAddress.lowercased()
        })
        let initialStateRequest = Task { [weak self] in
            guard let self else { return }
            await self.loadContractStates(for: initialRecords)
        }

        var discoveredStateRequest: Task<Void, Never>?
        do {
            let tokens = try await tokenRequest.value
            discoveredRecords = SRC721ContractRecord.insightDiscoveredRecords(
                from: tokens,
                accountId: accountId,
                chainId: service.chainId,
                walletAddress: walletAddress
            )
            reload()
            let discoveredContracts = records.filter {
                $0.transactionStatus == .confirmed && $0.contractType != .unknown &&
                    !initiallyLoadedAddresses.contains($0.contractAddress.lowercased())
            }
            discoveredStateRequest = Task { [weak self] in
                guard let self else { return }
                await self.loadContractStates(for: discoveredContracts)
            }
        } catch {
            loadError = error.localizedDescription
        }

        await initialStateRequest.value
        await discoveredStateRequest?.value
    }

    func refreshContract(_ record: SRC721ContractRecord) {
        reload()
        schedulePendingTransactionResolution()
        guard record.transactionStatus == .confirmed, record.contractType != .unknown else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.loadContractStates(for: [record])
        }
    }

    func removeFromList(_ record: SRC721ContractRecord) {
        guard canRemoveFromList(record) else { return }
        storage.hide(contract: record)
        contractStates.removeValue(forKey: record.contractAddress.lowercased())
        reload()
    }

    func hasPendingMint(for record: SRC721ContractRecord) -> Bool {
        pendingMintContractAddresses.contains(record.contractAddress.lowercased())
    }

    func canRemoveFromList(_ record: SRC721ContractRecord) -> Bool {
        guard record.transactionStatus == .confirmed else { return true }
        guard !hasPendingMint(for: record), let state = contractStates[record.contractAddress.lowercased()] else { return false }
        return state.totalSupply == 0
    }

    func remainingSupply(for record: SRC721ContractRecord, state: SRC721ContractSupplyState) -> BigUInt {
        let pendingMintAmount = pendingMintAmountsByContract[record.contractAddress.lowercased()] ?? .zero
        return pendingMintAmount >= state.remainSupply ? .zero : state.remainSupply - pendingMintAmount
    }

    private func schedulePendingTransactionResolution() {
        guard !isResolvingPendingTransactions else { return }

        var seenHashes = Set<String>()
        let deploymentTargets = records.compactMap { record -> SRC721PendingReceiptTarget? in
            guard record.transactionStatus == .pending, let hash = record.deployTransactionHash,
                  seenHashes.insert(hash.lowercased()).inserted else { return nil }
            return .deployment(record)
        }
        let operationTargets = transactionSnapshot.compactMap { transaction -> SRC721PendingReceiptTarget? in
            guard transaction.status == .pending,
                  seenHashes.insert(transaction.transactionHash.lowercased()).inserted else { return nil }
            return .transaction(transaction)
        }
        let targets = deploymentTargets + operationTargets
        guard !targets.isEmpty else { return }

        isResolvingPendingTransactions = true
        let receiptService = service
        Task { [weak self] in
            guard let self else { return }
            let resolutions = await withTaskGroup(of: SRC721PendingReceiptResponse.self) { group in
                var nextTargetIndex = 0
                for _ in 0..<min(Self.maximumConcurrentReceiptRequests, targets.count) {
                    self.addReceiptRequest(targets[nextTargetIndex], service: receiptService, to: &group)
                    nextTargetIndex += 1
                }

                var results: [SRC721PendingReceiptResponse] = []
                while let response = await group.next() {
                    results.append(response)
                    if nextTargetIndex < targets.count {
                        self.addReceiptRequest(targets[nextTargetIndex], service: receiptService, to: &group)
                        nextTargetIndex += 1
                    }
                }
                return results
            }

            var affectedAddresses = Set<String>()
            for resolution in resolutions {
                guard let success = resolution.success else { continue }
                switch resolution.target {
                case var .deployment(record):
                    record.transactionStatus = success ? .confirmed : .failed
                    if success, let address = resolution.deployedContractAddress {
                        record.contractAddress = address
                    }
                    self.storage.update(contract: record)
                    if success, let address = Web3Core.EthereumAddress(record.contractAddress)?.address.lowercased() {
                        affectedAddresses.insert(address)
                    }
                case var .transaction(transaction):
                    transaction.status = success ? .confirmed : .failed
                    transaction.errorMessage = success ? nil : "safe_zone.src721.error.transaction".localized
                    self.storage.save(transaction: transaction)
                    if let address = Web3Core.EthereumAddress(transaction.contractAddress)?.address.lowercased() {
                        affectedAddresses.insert(address)
                    }
                }
            }

            self.reload()
            let affectedContracts = self.records.filter { affectedAddresses.contains($0.contractAddress.lowercased()) }
            await self.loadContractStates(for: affectedContracts)
            self.isResolvingPendingTransactions = false

            let processedHashes = Set(targets.map { $0.transactionHash.lowercased() })
            let hasNewPendingTransaction = self.records.contains {
                $0.transactionStatus == .pending &&
                    $0.deployTransactionHash.map { !processedHashes.contains($0.lowercased()) } == true
            } || self.transactionSnapshot.contains {
                $0.status == .pending && !processedHashes.contains($0.transactionHash.lowercased())
            }
            if hasNewPendingTransaction {
                self.schedulePendingTransactionResolution()
            }
        }
    }

    private func addReceiptRequest(
        _ target: SRC721PendingReceiptTarget,
        service: SRC721Service,
        to group: inout TaskGroup<SRC721PendingReceiptResponse>
    ) {
        group.addTask {
            do {
                let success = try await service.waitForTransaction(target.transactionHash)
                let deployedAddress: String?
                if case .deployment = target, success {
                    deployedAddress = try? await service.deployedContractAddress(for: target.transactionHash)
                } else {
                    deployedAddress = nil
                }
                return SRC721PendingReceiptResponse(target: target, success: success, deployedContractAddress: deployedAddress)
            } catch {
                return SRC721PendingReceiptResponse(target: target, success: nil, deployedContractAddress: nil)
            }
        }
    }

    private func loadContractStates(for contracts: [SRC721ContractRecord]) async {
        let contractsToLoad = Dictionary(
            contracts.filter { $0.transactionStatus == .confirmed && $0.contractType != .unknown }
                .map { ($0.contractAddress.lowercased(), $0) },
            uniquingKeysWith: { _, latest in latest }
        ).values.sorted { $0.contractAddress < $1.contractAddress }
        guard !contractsToLoad.isEmpty else { return }

        let requests = contractsToLoad.map { record -> (record: SRC721ContractRecord, requestID: UUID, task: Task<SRC721ContractStateResponse, Never>) in
            let address = record.contractAddress.lowercased()
            if let existing = contractStateRequests[address] {
                return (record, existing.id, existing.task)
            }

            let requestID = UUID()
            let stateService = service
            let requestLimiter = contractStateRequestLimiter
            let task = Task {
                await requestLimiter.acquire()
                do {
                    let state = try await stateService.binding(contractAddress: record.contractAddress).supplyState(type: record.contractType)
                    await requestLimiter.release()
                    return SRC721ContractStateResponse(record: record, requestID: requestID, result: .success(state))
                } catch {
                    await requestLimiter.release()
                    return SRC721ContractStateResponse(record: record, requestID: requestID, result: .failure(error))
                }
            }
            contractStateRequestIDs[address] = requestID
            contractStateRequests[address] = (requestID, task)
            loadingContractAddresses.insert(address)
            return (record, requestID, task)
        }
        for request in requests {
            let address = request.record.contractAddress.lowercased()
            if contractStateRequestIDs[address] == request.requestID {
                loadingContractAddresses.insert(address)
            }
        }

        await withTaskGroup(of: SRC721ContractStateResponse.self) { group in
            for request in requests {
                group.addTask { await request.task.value }
            }

            while let response = await group.next() {
                let address = response.record.contractAddress.lowercased()
                if contractStateRequestIDs[address] == response.requestID {
                    loadingContractAddresses.remove(address)
                    contractStateRequests.removeValue(forKey: address)
                    if case let .success(state) = response.result {
                        contractStates[address] = state
                    }
                }
            }
        }
    }

}

@MainActor
final class SRC721WalletAssetsViewModel: ObservableObject {
    private static let pageSize = 50
    private static let maximumTokensPerContract = 500
    private static let maximumConcurrentInsightRequests = 4
    private static let maximumConcurrentLocalContractRequests = 4

    private let service: SRC721Service
    private let storage: SRC721Storage
    private let accountId: String
    private let walletAddress: String

    @Published private(set) var assets: [SRC721WalletAsset] = []
    @Published private(set) var collections: [SRC721WalletCollection] = []
    @Published private(set) var dataState: SRC721DataState = .loading
    @Published private(set) var isTruncated = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var hasLoadErrors = false

    private var refreshID = UUID()
    private var refreshRequestedWhileLoading = false
    private var insightCatalogByAddress: [String: SRC721InsightToken] = [:]

    private var pendingTokenOperations: [String: SRC721TransactionOperation] {
        Dictionary(
            storage.transactions(accountId: accountId, chainId: service.chainId, walletAddress: walletAddress)
                .filter { $0.status == .pending && $0.tokenOperation != nil }
                .compactMap { transaction in
                    guard let tokenId = transaction.tokenId,
                          let operation = transaction.tokenOperation,
                          Web3Core.EthereumAddress(transaction.contractAddress)?.address != nil else {
                        return nil
                    }
                    let contractAddress = Web3Core.EthereumAddress(transaction.contractAddress)?.address.lowercased() ?? transaction.contractAddress.lowercased()
                    return ("\(contractAddress):\(tokenId)", operation)
                },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    init(service: SRC721Service, storage: SRC721Storage, accountId: String, walletAddress: String) {
        self.service = service
        self.storage = storage
        self.accountId = accountId
        self.walletAddress = walletAddress
        refresh()
    }

    func refresh() {
        guard !isRefreshing else {
            refreshRequestedWhileLoading = true
            return
        }
        isRefreshing = true
        let requestID = UUID()
        refreshID = requestID
        let previousAssets = assets
        if assets.isEmpty {
            dataState = .loading
        }
        isTruncated = false
        hasLoadErrors = false
        let records = storage.contracts(accountId: accountId, chainId: service.chainId, walletAddress: walletAddress)
            .filter { $0.transactionStatus == .confirmed && $0.contractType != .unknown }
        let pendingOperations = pendingTokenOperations

        Task { [weak self] in
            guard let self else { return }
            let tokenCatalogRequest = Task { await self.fetchInsightTokenCatalog() }
            Task { [weak self] in
                guard case let .success(catalog) = await tokenCatalogRequest.value,
                      let self,
                      self.refreshID == requestID else { return }
                self.applyInsightCatalog(catalog, requestID: requestID)
            }
            let holdingsResult = await fetchInsightHoldings()

            let knownRecords = Dictionary(
                records.compactMap { record -> (String, SRC721ContractRecord)? in
                    guard let address = Web3Core.EthereumAddress(record.contractAddress)?.address else { return nil }
                    return (address.lowercased(), record)
                },
                uniquingKeysWith: { first, _ in first }
            )
            var loadedAssetsByID: [String: SRC721WalletAsset] = [:]
            var insightLoadedContracts = Set<String>()
            var hasLoadErrors = false
            var insightRequestError: String?
            var insightDetailError: String?

            let holdings: [SRC721InsightHolding]?
            switch holdingsResult {
            case let .success(value):
                holdings = value
            case let .failure(error):
                holdings = nil
                hasLoadErrors = true
                insightRequestError = error.localizedDescription
            }

            if let holdings,
               let normalizedWalletAddress = Web3Core.EthereumAddress(walletAddress)?.address {
                var holdingAddresses = Set<String>()
                let requests = holdings.compactMap { holding -> SRC721InsightContractRequest? in
                    guard holding.owner.caseInsensitiveCompare(normalizedWalletAddress) == .orderedSame,
                          let address = Web3Core.EthereumAddress(holding.token)?.address else { return nil }
                    let key = address.lowercased()
                    guard holdingAddresses.insert(key).inserted else { return nil }
                    return SRC721InsightContractRequest(key: key, address: address)
                }

                let service = self.service
                await withTaskGroup(of: SRC721InsightContractResponse.self) { group in
                    var nextRequestIndex = 0
                    for _ in 0..<min(Self.maximumConcurrentInsightRequests, requests.count) {
                        self.addInsightAssetsRequest(requests[nextRequestIndex], service: service, to: &group)
                        nextRequestIndex += 1
                    }

                    while let response = await group.next() {
                        if nextRequestIndex < requests.count {
                            self.addInsightAssetsRequest(requests[nextRequestIndex], service: service, to: &group)
                            nextRequestIndex += 1
                        }

                        let indexedAssets: [SRC721InsightAsset]
                        switch response.result {
                        case let .success(value):
                            indexedAssets = value
                            insightLoadedContracts.insert(response.request.key)
                        case let .failure(error):
                            hasLoadErrors = true
                            if insightDetailError == nil { insightDetailError = error.localizedDescription }
                            continue
                        }

                        let contract = knownRecords[response.request.key] ?? SRC721ContractRecord(
                            accountId: self.accountId,
                            chainId: service.chainId,
                            walletAddress: normalizedWalletAddress,
                            contractAddress: response.request.address,
                            predictedContractAddress: nil,
                            creatorAddress: "",
                            currentOwnerAddress: nil,
                            contractType: .generic,
                            name: "",
                            symbol: "",
                            baseURI: "",
                            maxSupply: "0",
                            mintPrice: "0",
                            deployTransactionHash: nil,
                            transactionStatus: .confirmed,
                            validationStatus: "insight",
                            createdAt: Date(timeIntervalSince1970: 0)
                        )

                        // The list uses the indexer snapshot; exact ownership is checked in token detail before actions are enabled.
                        for indexedAsset in indexedAssets {
                            guard indexedAsset.isERC721,
                                  Web3Core.EthereumAddress(indexedAsset.token)?.address.lowercased() == response.request.key,
                                  Web3Core.EthereumAddress(indexedAsset.owner)?.address.lowercased() == normalizedWalletAddress.lowercased(),
                                  let tokenId = BigUInt(indexedAsset.tokenId) else { continue }
                            let assetKey = "\(response.request.key):\(tokenId.description)"
                            let token = SRC721OwnedToken(
                                tokenId: tokenId,
                                ownerAddress: normalizedWalletAddress,
                                tokenURI: indexedAsset.tokenURI,
                                imageURL: indexedAsset.tokenImage,
                                source: .indexer
                            )
                            loadedAssetsByID["\(contract.id):\(tokenId.description)"] = SRC721WalletAsset(
                                contract: contract,
                                token: token,
                                pendingOperation: pendingOperations[assetKey]
                            )
                        }

                        self.publishLoadedAssets(loadedAssetsByID, requestID: requestID)
                    }
                }
            }

            var didLoadAnyLocalContract = false
            var truncated = false
            let localRequests = records.compactMap { record -> SRC721LocalContractRequest? in
                guard let address = Web3Core.EthereumAddress(record.contractAddress)?.address else { return nil }
                let key = address.lowercased()
                guard !insightLoadedContracts.contains(key) else { return nil }
                return SRC721LocalContractRequest(record: record, key: key, address: address)
            }
            await withTaskGroup(of: SRC721LocalContractPageResponse.self) { group in
                var nextRequestIndex = 0
                for _ in 0..<min(Self.maximumConcurrentLocalContractRequests, localRequests.count) {
                    self.addLocalAssetsPageRequest(
                        localRequests[nextRequestIndex],
                        offset: 0,
                        loadedCount: 0,
                        service: service,
                        to: &group
                    )
                    nextRequestIndex += 1
                }

                while let response = await group.next() {
                    var didScheduleNextPage = false
                    switch response.result {
                    case let .success(page):
                        didLoadAnyLocalContract = true
                        for token in page.tokens {
                            let pendingOperation = pendingOperations["\(response.request.key):\(token.tokenId.description)"]
                            let asset = SRC721WalletAsset(contract: response.request.record, token: token, pendingOperation: pendingOperation)
                            loadedAssetsByID[asset.id] = asset
                        }
                        self.publishLoadedAssets(loadedAssetsByID, requestID: requestID)

                        let loadedCount = response.loadedCount + page.tokens.count
                        do {
                            let offset = try SRC721OwnedTokenPaging.nextOffset(
                                offset: response.offset,
                                total: page.total,
                                returnedCount: page.tokens.count,
                                limit: Self.pageSize
                            )
                            let hasMore = SRC721OwnedTokenPaging.hasMore(offset: offset, total: page.total)
                            if hasMore && loadedCount < Self.maximumTokensPerContract {
                                self.addLocalAssetsPageRequest(
                                    response.request,
                                    offset: offset,
                                    loadedCount: loadedCount,
                                    service: service,
                                    to: &group
                                )
                                didScheduleNextPage = true
                            } else {
                                truncated = truncated || hasMore
                            }
                        } catch {
                            hasLoadErrors = true
                            if insightDetailError == nil { insightDetailError = error.localizedDescription }
                        }
                    case let .failure(error):
                        hasLoadErrors = true
                        if insightDetailError == nil { insightDetailError = error.localizedDescription }
                    }

                    if !didScheduleNextPage, nextRequestIndex < localRequests.count {
                        self.addLocalAssetsPageRequest(
                            localRequests[nextRequestIndex],
                            offset: 0,
                            loadedCount: 0,
                            service: service,
                            to: &group
                        )
                        nextRequestIndex += 1
                    }
                }
            }

            // Keep a token visible while a transfer/burn receipt is uncertain,
            // even if the indexer has already reflected the new owner.
            let pendingTransactions = storage.transactions(
                accountId: accountId,
                chainId: service.chainId,
                walletAddress: walletAddress
            ).filter { transaction in
                transaction.status == .pending &&
                    transaction.tokenId != nil &&
                    transaction.tokenOperation != nil
            }
            for transaction in pendingTransactions {
                guard let tokenIdString = transaction.tokenId,
                      let tokenId = BigUInt(tokenIdString),
                      let contract = records.first(where: {
                          Web3Core.EthereumAddress($0.contractAddress)?.address.caseInsensitiveCompare(transaction.contractAddress) == .orderedSame
                      }) else { continue }
                let assetID = "\(contract.id):\(tokenId.description)"
                guard loadedAssetsByID[assetID] == nil else { continue }
                let token = SRC721OwnedToken(tokenId: tokenId, ownerAddress: walletAddress, tokenURI: nil, source: .onChain)
                loadedAssetsByID[assetID] = SRC721WalletAsset(contract: contract, token: token, pendingOperation: transaction.tokenOperation)
            }

            let containsInsightAssets = loadedAssetsByID.values.contains(where: { $0.contract.isInsightDiscovered })
            if loadedAssetsByID.isEmpty && hasLoadErrors {
                loadedAssetsByID = Dictionary(uniqueKeysWithValues: previousAssets.map { ($0.id, $0) })
            }
            if !containsInsightAssets {
                tokenCatalogRequest.cancel()
            }

            guard refreshID == requestID else { return }
            let loadedAssets = loadedAssetsByID.values.map { self.applyingInsightCatalog(to: $0) }
            assets = loadedAssets
            collections = SRC721WalletCollection.grouped(assets: loadedAssets)
            isTruncated = truncated
            self.hasLoadErrors = hasLoadErrors
            if loadedAssets.isEmpty && hasLoadErrors && !didLoadAnyLocalContract {
                dataState = .failed(insightRequestError ?? insightDetailError ?? "safe_zone.src721.error.enumeration_unavailable".localized)
            } else {
                dataState = .completed
            }
            isRefreshing = false
            if refreshRequestedWhileLoading {
                refreshRequestedWhileLoading = false
                refresh()
                return
            }

            guard containsInsightAssets else { return }
            Task { [weak self] in
                guard let self else { return }
                guard case let .success(catalog) = await tokenCatalogRequest.value else {
                    guard refreshID == requestID else { return }
                    hasLoadErrors = true
                    return
                }
                applyInsightCatalog(catalog, requestID: requestID)
            }
        }
    }

    func updateAsset(_ asset: SRC721WalletAsset, pendingOperation: SRC721TransactionOperation?) {
        guard let index = assets.firstIndex(where: { $0.id == asset.id }) else { return }
        assets[index] = SRC721WalletAsset(contract: assets[index].contract, token: assets[index].token, pendingOperation: pendingOperation)
        collections = SRC721WalletCollection.grouped(assets: assets)
    }

    func removeAsset(_ asset: SRC721WalletAsset) {
        assets.removeAll { $0.id == asset.id }
        collections = SRC721WalletCollection.grouped(assets: assets)
        dataState = .completed
    }

    private func fetchInsightTokenCatalog() async -> Result<[SRC721InsightToken], Error> {
        do {
            return .success(try await service.insightTokens())
        } catch {
            return .failure(error)
        }
    }

    private func fetchInsightHoldings() async -> Result<[SRC721InsightHolding], Error> {
        do {
            return .success(try await service.insightHoldings())
        } catch {
            return .failure(error)
        }
    }

    private func addInsightAssetsRequest(
        _ request: SRC721InsightContractRequest,
        service: SRC721Service,
        to group: inout TaskGroup<SRC721InsightContractResponse>
    ) {
        group.addTask {
            do {
                let assets = try await service.insightAssets(tokenAddress: request.address)
                return SRC721InsightContractResponse(request: request, result: .success(assets))
            } catch {
                return SRC721InsightContractResponse(request: request, result: .failure(error))
            }
        }
    }

    private func addLocalAssetsPageRequest(
        _ request: SRC721LocalContractRequest,
        offset: Int,
        loadedCount: Int,
        service: SRC721Service,
        to group: inout TaskGroup<SRC721LocalContractPageResponse>
    ) {
        group.addTask {
            do {
                let page = try await service.binding(contractAddress: request.address)
                    .ownedTokenPage(type: request.record.contractType, offset: offset, limit: Self.pageSize)
                return SRC721LocalContractPageResponse(
                    request: request,
                    offset: offset,
                    loadedCount: loadedCount,
                    result: .success(page)
                )
            } catch {
                return SRC721LocalContractPageResponse(
                    request: request,
                    offset: offset,
                    loadedCount: loadedCount,
                    result: .failure(error)
                )
            }
        }
    }

    private func publishLoadedAssets(_ loadedAssetsByID: [String: SRC721WalletAsset], requestID: UUID) {
        guard refreshID == requestID else { return }
        var visibleAssetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        loadedAssetsByID.forEach { visibleAssetsByID[$0.key] = $0.value }
        let loadedAssets = visibleAssetsByID.values.map { applyingInsightCatalog(to: $0) }
        assets = loadedAssets
        collections = SRC721WalletCollection.grouped(assets: loadedAssets)
        if !loadedAssets.isEmpty {
            dataState = .completed
        }
    }

    private func applyInsightCatalog(_ catalog: [SRC721InsightToken], requestID: UUID) {
        guard refreshID == requestID else { return }
        insightCatalogByAddress = Dictionary(
            catalog.filter(\.isERC721).compactMap { token -> (String, SRC721InsightToken)? in
                guard let address = Web3Core.EthereumAddress(token.address)?.address else { return nil }
                return (address.lowercased(), token)
            },
            uniquingKeysWith: { first, _ in first }
        )
        assets = assets.map { applyingInsightCatalog(to: $0) }
        collections = SRC721WalletCollection.grouped(assets: assets)
    }

    private func applyingInsightCatalog(to asset: SRC721WalletAsset) -> SRC721WalletAsset {
        guard asset.contract.isInsightDiscovered,
              let tokenInfo = insightCatalogByAddress[asset.contract.contractAddress.lowercased()] else { return asset }
        let contract = SRC721ContractRecord(
            accountId: asset.contract.accountId,
            chainId: asset.contract.chainId,
            walletAddress: asset.contract.walletAddress,
            contractAddress: asset.contract.contractAddress,
            predictedContractAddress: asset.contract.predictedContractAddress,
            creatorAddress: tokenInfo.creator,
            currentOwnerAddress: asset.contract.currentOwnerAddress,
            contractType: tokenInfo.src721ContractType,
            name: tokenInfo.name,
            symbol: tokenInfo.symbol,
            baseURI: asset.contract.baseURI,
            maxSupply: asset.contract.maxSupply,
            mintPrice: asset.contract.mintPrice,
            deployTransactionHash: asset.contract.deployTransactionHash,
            transactionStatus: asset.contract.transactionStatus,
            validationStatus: asset.contract.validationStatus,
            createdAt: asset.contract.createdAt
        )
        let token = SRC721OwnedToken(
            tokenId: asset.token.tokenId,
            ownerAddress: asset.token.ownerAddress,
            tokenURI: asset.token.tokenURI,
            imageURL: asset.token.imageURL ?? tokenInfo.logoURI,
            source: asset.token.source
        )
        return SRC721WalletAsset(contract: contract, token: token, pendingOperation: asset.pendingOperation)
    }
}

private struct SRC721ContractStateResponse {
    let record: SRC721ContractRecord
    let requestID: UUID
    let result: Result<SRC721ContractSupplyState, Error>
}

private enum SRC721PendingReceiptTarget {
    case deployment(SRC721ContractRecord)
    case transaction(SRC721TransactionRecord)

    var transactionHash: String {
        switch self {
        case let .deployment(record):
            return record.deployTransactionHash ?? ""
        case let .transaction(record):
            return record.transactionHash
        }
    }
}

private struct SRC721PendingReceiptResponse {
    let target: SRC721PendingReceiptTarget
    let success: Bool?
    let deployedContractAddress: String?
}

private actor SRC721AsyncRequestLimiter {
    private let maximumConcurrentRequests: Int
    private var activeRequests = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maximumConcurrentRequests: Int) {
        self.maximumConcurrentRequests = maximumConcurrentRequests
    }

    func acquire() async {
        if activeRequests < maximumConcurrentRequests {
            activeRequests += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            activeRequests -= 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}

private struct SRC721InsightContractRequest {
    let key: String
    let address: String
}

private struct SRC721InsightContractResponse {
    let request: SRC721InsightContractRequest
    let result: Result<[SRC721InsightAsset], Error>
}

private struct SRC721LocalContractRequest {
    let record: SRC721ContractRecord
    let key: String
    let address: String
}

private struct SRC721LocalContractPageResponse {
    let request: SRC721LocalContractRequest
    let offset: Int
    let loadedCount: Int
    let result: Result<SRC721OwnedTokenPage, Error>
}

@MainActor
final class SRC721AllowListViewModel: ObservableObject {
    private static let pageSize = BigUInt(SRC721AllowListPage.maximumCount)

    let record: SRC721ContractRecord
    private let service: SRC721Service
    private let storage: SRC721Storage

    @Published private(set) var entries: [SRC721AllowListEntry] = []
    @Published private(set) var dataState: SRC721DataState = .loading
    @Published private(set) var hasMore = false
    @Published private(set) var isLoadingNextPage = false
    @Published private(set) var loadMoreError: String?
    @Published private(set) var isOwner = false
    @Published private(set) var operationState: SRC721AsyncState = .idle
    @Published private(set) var submissionID = UUID()
    @Published var operationMessage: String?
    @Published private(set) var operationHashes: [String] = []
    @Published var address = ""
    @Published var amount = ""
    @Published var addressCautionState: CautionState = .none
    @Published var amountCautionState: CautionState = .none
    @Published private(set) var editingEntry: SRC721AllowListEntry?
    @Published private(set) var invalidField: SRC721AllowListEditorField?
    @Published private(set) var validationRequestID = UUID()

    private var nextStart = BigUInt.zero
    private var refreshID = UUID()

    var canTransact: Bool { service.canSign }

    init(record: SRC721ContractRecord, service: SRC721Service, storage: SRC721Storage) {
        self.record = record
        self.service = service
        self.storage = storage
        refresh()
    }

    func refresh() {
        let requestID = UUID()
        refreshID = requestID
        entries = []
        isOwner = false
        nextStart = .zero
        hasMore = false
        isLoadingNextPage = false
        loadMoreError = nil
        dataState = .loading
        Task { [weak self] in
            guard let self else { return }
            do {
                let record = self.record
                let page = try await service.allowListPage(type: record.contractType, start: .zero, count: Self.pageSize)
                let ownerAddress = try? await service.ownerAddress(type: record.contractType)
                let chainEntries = page.entries.map { entry in
                    SRC721AllowListEntry(
                        accountId: record.accountId,
                        chainId: record.chainId,
                        walletAddress: record.walletAddress,
                        contractAddress: record.contractAddress,
                        address: entry.address,
                        amount: entry.amount.description,
                        transactionHash: "",
                        updatedAt: .distantPast
                    )
                }
                await MainActor.run {
                    guard self.refreshID == requestID else { return }
                    self.entries = chainEntries.sorted { $0.address.localizedCaseInsensitiveCompare($1.address) == .orderedAscending }
                    self.nextStart = page.nextStart
                    self.hasMore = page.hasMore
                    self.isOwner = ownerAddress?.lowercased() == self.service.userAddress.lowercased()
                    if ownerAddress == nil {
                        self.loadMoreError = "safe_zone.src721.error.owner_read_failed".localized
                    }
                    self.dataState = .completed
                }
            } catch {
                await MainActor.run {
                    guard self.refreshID == requestID else { return }
                    if error is SRC721ValidationError,
                       case SRC721ValidationError.allowListUnavailable = error {
                        self.dataState = .unavailable(error.localizedDescription)
                    } else {
                        self.dataState = .failed(error.localizedDescription)
                    }
                }
            }
        }
    }

    func loadNextPage() {
        guard hasMore, !isLoadingNextPage, dataState == .completed else { return }
        let requestID = refreshID
        let start = nextStart
        isLoadingNextPage = true
        loadMoreError = nil

        Task { [weak self] in
            guard let self else { return }
            do {
                let record = self.record
                let page = try await service.allowListPage(type: record.contractType, start: start, count: Self.pageSize)
                let newEntries = page.entries.map { entry in
                    SRC721AllowListEntry(
                        accountId: record.accountId,
                        chainId: record.chainId,
                        walletAddress: record.walletAddress,
                        contractAddress: record.contractAddress,
                        address: entry.address,
                        amount: entry.amount.description,
                        transactionHash: "",
                        updatedAt: .distantPast
                    )
                }
                await MainActor.run {
                    guard self.refreshID == requestID else { return }
                    let loaded = Dictionary(self.entries.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
                    let additions = Dictionary(newEntries.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
                    self.entries = Array(loaded.merging(additions, uniquingKeysWith: { _, latest in latest }).values)
                        .sorted { $0.address.localizedCaseInsensitiveCompare($1.address) == .orderedAscending }
                    self.nextStart = page.nextStart
                    self.hasMore = page.hasMore
                    self.isLoadingNextPage = false
                }
            } catch {
                await MainActor.run {
                    guard self.refreshID == requestID else { return }
                    self.loadMoreError = error.localizedDescription
                    self.isLoadingNextPage = false
                }
            }
        }
    }

    func beginAdding() {
        editingEntry = nil
        address = ""
        amount = ""
        clearValidation()
        operationState = .idle
        operationMessage = nil
        operationHashes = []
    }

    func beginEditing(_ entry: SRC721AllowListEntry) {
        editingEntry = entry
        address = entry.address
        amount = entry.amount
        clearValidation()
        operationState = .idle
        operationMessage = nil
        operationHashes = []
    }

    func submit() {
        guard operationState != .sending, validate() else { return }
        guard isOwner else {
            showOperationError("safe_zone.src721.error.owner_required".localized)
            return
        }
        guard let parsedAddress = try? SRC721Validation.address(address, field: "safe_zone.src721.field.address".localized),
              let parsedAmount = try? SRC721Validation.amount(amount, field: "safe_zone.src721.field.amount".localized, allowZero: true) else {
            return
        }

        let isEditing = editingEntry != nil
        let operationName = "safe_zone.src721.action.set_allow_list".localized
        operationState = .sending
        operationMessage = nil
        operationHashes = []
        Task { [weak self, service, storage, record] in
            guard let self else { return }
            do {
                let hash = try await service.setAllowList(type: record.contractType, addresses: [parsedAddress], amounts: [parsedAmount])
                await MainActor.run { self.submissionID = UUID() }
                let transactionID = UUID()
                let createdAt = Date()
                storage.save(transaction: SRC721TransactionRecord(
                    id: transactionID, accountId: record.accountId, chainId: record.chainId,
                    walletAddress: record.walletAddress, contractAddress: record.contractAddress,
                    operation: operationName, tokenId: nil, transactionHash: hash, status: .pending,
                    errorMessage: nil, createdAt: createdAt
                ))
                let success = try await service.waitForTransaction(hash)
                storage.save(transaction: SRC721TransactionRecord(
                    id: transactionID, accountId: record.accountId, chainId: record.chainId,
                    walletAddress: record.walletAddress, contractAddress: record.contractAddress,
                    operation: operationName, tokenId: nil, transactionHash: hash,
                    status: success ? .confirmed : .failed,
                    errorMessage: success ? nil : "safe_zone.src721.error.transaction".localized,
                    createdAt: createdAt
                ))
                guard success else { throw Web3Error.processingError(desc: "safe_zone.src721.error.transaction".localized) }

                let entry = SRC721AllowListEntry(
                    accountId: record.accountId, chainId: record.chainId, walletAddress: record.walletAddress,
                    contractAddress: record.contractAddress, address: parsedAddress.address,
                    amount: parsedAmount.description, transactionHash: hash, updatedAt: Date()
                )
                storage.save(allowListEntry: entry)
                await MainActor.run {
                    self.operationMessage = (isEditing
                        ? "safe_zone.src721.allow_list.edit.success"
                        : "safe_zone.src721.allow_list.add.success").localized
                    self.operationHashes = [hash]
                    self.operationState = .completed
                }
                refresh()
            } catch {
                await MainActor.run {
                    self.operationState = .failed
                    self.operationMessage = error.localizedDescription
                }
            }
        }
    }

    private func validate() -> Bool {
        clearValidation()
        var isValid = true
        do {
            _ = try SRC721Validation.address(address, field: "safe_zone.src721.field.address".localized)
        } catch {
            addressCautionState = .caution(Caution(text: error.localizedDescription, type: .error))
            invalidField = .address
            isValid = false
        }
        do {
            _ = try SRC721Validation.amount(amount, field: "safe_zone.src721.field.amount".localized, allowZero: true)
        } catch {
            amountCautionState = .caution(Caution(text: error.localizedDescription, type: .error))
            invalidField = invalidField ?? .amount
            isValid = false
        }
        if isValid, let address = try? SRC721Validation.address(address, field: "safe_zone.src721.field.address".localized) {
            let normalizedAddress = address.address.lowercased()
            let isDuplicate = entries.contains {
                $0.address.lowercased() == normalizedAddress && $0.id != editingEntry?.id
            }
            if isDuplicate {
                addressCautionState = .caution(Caution(text: "safe_zone.src721.error.allow_list_duplicate".localized, type: .error))
                invalidField = .address
                isValid = false
            }
        }
        validationRequestID = UUID()
        return isValid
    }

    private func clearValidation() {
        addressCautionState = .none
        amountCautionState = .none
        invalidField = nil
    }

    private func showOperationError(_ message: String) {
        operationState = .failed
        operationMessage = message
        operationHashes = []
    }
}

@MainActor
final class SRC721ImportViewModel: ObservableObject {
    private let service: SRC721Service
    private let storage: SRC721Storage
    private let accountId: String
    private let walletAddress: String

    @Published var address = ""
    @Published var type: SRC721ContractType = .standard
    @Published var state: SRC721AsyncState = .idle
    @Published var errorMessage: String?
    @Published var addressCautionState: CautionState = .none
    @Published private(set) var invalidField: SRC721ImportField?
    @Published private(set) var validationRequestID = UUID()

    init(service: SRC721Service, storage: SRC721Storage, accountId: String, walletAddress: String) {
        self.service = service
        self.storage = storage
        self.accountId = accountId
        self.walletAddress = walletAddress
    }

    func validateForSubmit() -> Bool {
        addressCautionState = .none
        invalidField = nil
        do {
            _ = try SRC721Validation.address(address, field: "safe_zone.src721.field.contract".localized)
            return true
        } catch {
            addressCautionState = .caution(Caution(text: error.localizedDescription, type: .error))
            invalidField = .address
            validationRequestID = UUID()
            return false
        }
    }

    func importContract() {
        guard state != .sending, validateForSubmit() else { return }
        state = .sending
        errorMessage = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                let contractAddress = try SRC721Validation.address(address, field: "safe_zone.src721.field.contract".localized).address
                let contractService = SRC721Service(privateKey: Data(), userAddress: walletAddress, chainId: service.chainId, contractAddress: contractAddress)
                let state = try await contractService.validateContract(type: type)
                let record = SRC721ContractRecord(
                    accountId: accountId,
                    chainId: service.chainId,
                    walletAddress: walletAddress,
                    contractAddress: contractAddress,
                    predictedContractAddress: nil,
                    creatorAddress: "",
                    currentOwnerAddress: state.ownerAddress,
                    contractType: type,
                    name: state.name,
                    symbol: state.symbol,
                    baseURI: state.baseURI,
                    maxSupply: state.maxSupply.description,
                    mintPrice: state.mintPrice.description,
                    deployTransactionHash: nil,
                    transactionStatus: .confirmed,
                    validationStatus: "manual",
                    createdAt: Date()
                )
                storage.save(contract: record)
                await MainActor.run { self.state = .completed }
            } catch {
                await MainActor.run {
                    self.state = .failed
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

@MainActor
final class SRC721ContractDetailViewModel: ObservableObject {
    let record: SRC721ContractRecord
    private let service: SRC721Service
    private let storage: SRC721Storage
    private let loadsContractState: Bool
    private let loadsTokenURI: Bool

    @Published private(set) var contractState: SRC721ContractState?
    @Published private(set) var tokenState: SRC721TokenState?
    @Published private(set) var detectedContractType: SRC721ContractType?
    @Published private(set) var isDetectingContractType = false
    @Published private(set) var isLoadingToken = false
    @Published private(set) var tokenLoadError: String?
    @Published private(set) var tokenNoLongerExists = false
    @Published private(set) var burnedTokenId: BigUInt?
    @Published private(set) var dataState: SRC721DataState = .loading
    @Published private(set) var isRefreshing = false
    @Published private(set) var refreshErrorMessage: String?
    @Published private(set) var operationState: SRC721AsyncState = .idle
    @Published private(set) var isSubmittingOperation = false
    @Published private(set) var submissionID = UUID()
    @Published var operationMessage: String?
    @Published private(set) var operationHashes: [String] = []
    @Published var tokenId = ""
    @Published var baseURICautionState: CautionState = .none
    @Published var maxSupplyCautionState: CautionState = .none
    @Published var mintPriceCautionState: CautionState = .none
    @Published var orgNameCautionState: CautionState = .none
    @Published var descriptionCautionState: CautionState = .none
    @Published var officialURLCautionState: CautionState = .none
    @Published var whitePaperURLCautionState: CautionState = .none
    @Published var logoCautionState: CautionState = .none
    @Published var mintRecipientCautionState: CautionState = .none
    @Published var mintAmountCautionState: CautionState = .none
    @Published var tokenIdCautionState: CautionState = .none
    @Published var tokenRecipientCautionState: CautionState = .none
    @Published var operatorCautionState: CautionState = .none
    @Published private(set) var invalidField: SRC721DetailField?
    @Published private(set) var validationRequestID = UUID()

    var canManage: Bool {
        Self.isOwner(ownerAddress: contractState?.ownerAddress, walletAddress: service.userAddress)
    }

    static func isOwner(ownerAddress: String?, walletAddress: String) -> Bool {
        guard let ownerAddress,
              let owner = Web3Core.EthereumAddress(ownerAddress),
              let wallet = Web3Core.EthereumAddress(walletAddress) else { return false }
        return owner.address.caseInsensitiveCompare(wallet.address) == .orderedSame
    }

    var contractType: SRC721ContractType { detectedContractType ?? record.contractType }

    /// Type-specific operations remain disabled until a generic indexer record
    /// is identified as a supported Safe4 SRC721 implementation.
    var isContractTypeResolved: Bool {
        contractType == .standard || contractType == .burnable
    }

    var isContractStateReady: Bool {
        contractState != nil && dataState == .completed && !isRefreshing
    }

    var canTransact: Bool { service.canSign }

    var tokenOperationPending: Bool {
        pendingTokenOperation != nil
    }

    var pendingTokenOperation: SRC721TransactionOperation? {
        guard let tokenId = BigUInt(tokenId) else { return nil }
        return storage.transactions(accountId: record.accountId, chainId: record.chainId, walletAddress: record.walletAddress)
            .filter { transaction in
                transaction.status == .pending &&
                    transaction.tokenId == tokenId.description &&
                    Web3Core.EthereumAddress(transaction.contractAddress)?.address.caseInsensitiveCompare(record.contractAddress) == .orderedSame
            }
            .compactMap(\.tokenOperation)
            .first
    }

    var remainingSupply: BigUInt {
        guard let contractState else { return .zero }
        let pendingMintAmount = storage.transactions(accountId: record.accountId, chainId: record.chainId, walletAddress: record.walletAddress)
            .filter {
                $0.status == .pending && $0.operationKind == .mint &&
                    Web3Core.EthereumAddress($0.contractAddress)?.address.caseInsensitiveCompare(record.contractAddress) == .orderedSame
            }
            .compactMap { $0.amount.flatMap(BigUInt.init) }
            .reduce(BigUInt.zero, +)
        return pendingMintAmount >= contractState.remainSupply ? .zero : contractState.remainSupply - pendingMintAmount
    }

    func hasUpdateChanges(
        baseURI: String,
        maxSupply: String,
        mintPrice: String,
        orgName: String,
        description: String,
        officialURL: String,
        whitePaperURL: String,
        logo: Data?
    ) -> Bool {
        guard let current = contractState else { return false }
        let trimmedBaseURI = baseURI.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOrgName = orgName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOfficialURL = officialURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWhitePaperURL = whitePaperURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedBaseURI != current.baseURI ||
            BigUInt(maxSupply) != current.maxSupply ||
            BigUInt(mintPrice) != current.mintPrice ||
            trimmedOrgName != current.orgName ||
            trimmedDescription != current.description ||
            trimmedOfficialURL != current.officialURL ||
            trimmedWhitePaperURL != current.whitePaperURL ||
            logo != nil
    }

    private var refreshGeneration = 0
    private var tokenLoadGeneration = 0
    private var contractTypeRecognitionTask: Task<SRC721ContractType?, Never>?
    private var refreshTask: Task<Void, Never>?

    init(
        record: SRC721ContractRecord,
        service: SRC721Service,
        storage: SRC721Storage,
        loadsContractState: Bool = true,
        loadsTokenURI: Bool = true
    ) {
        self.record = record
        self.service = service
        self.storage = storage
        self.loadsContractState = loadsContractState
        self.loadsTokenURI = loadsTokenURI
        if loadsContractState, record.contractType != .generic {
            refresh()
        }
        detectContractTypeIfNeeded()
    }

    private func detectContractTypeIfNeeded() {
        guard record.contractType == .generic,
              detectedContractType == nil,
              contractTypeRecognitionTask == nil else { return }
        let service = self.service
        isDetectingContractType = true
        contractTypeRecognitionTask = Task { [weak self] in
            let detectedType: SRC721ContractType?
            do {
                detectedType = try await service.recognizedSRC721ContractType()
            } catch {
                detectedType = nil
            }
            guard let self else { return nil }
            self.isDetectingContractType = false
            if let detectedType {
                self.detectedContractType = detectedType
            }
            self.contractTypeRecognitionTask = nil
            self.refresh(retryContractTypeRecognition: false)
            return detectedType
        }
    }

    @discardableResult
    func refresh() -> Task<Void, Never>? {
        refresh(retryContractTypeRecognition: true)
    }

    @discardableResult
    private func refresh(retryContractTypeRecognition: Bool) -> Task<Void, Never>? {
        guard loadsContractState else { return nil }
        if isRefreshing, let refreshTask {
            return refreshTask
        }
        if retryContractTypeRecognition {
            detectContractTypeIfNeeded()
        }
        refreshGeneration += 1
        let generation = refreshGeneration
        let isInitialLoad = contractState == nil
        if isInitialLoad {
            dataState = .loading
        }
        isRefreshing = true
        refreshErrorMessage = nil
        let refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let state = try await service.state(type: contractType)
                await MainActor.run {
                    guard self.refreshGeneration == generation else { return }
                    self.contractState = state
                    self.dataState = .completed
                    self.isRefreshing = false
                    self.refreshErrorMessage = nil
                    self.updateStoredOwner(state.ownerAddress)
                    self.refreshTask = nil
                }
            } catch {
                await MainActor.run {
                    guard self.refreshGeneration == generation else { return }
                    self.isRefreshing = false
                    if isInitialLoad {
                        self.dataState = .failed(error.localizedDescription)
                    } else {
                        self.refreshErrorMessage = error.localizedDescription
                    }
                    self.refreshTask = nil
                }
            }
        }
        self.refreshTask = refreshTask
        return refreshTask
    }

    func loadToken(showError: Bool = true) {
        detectContractTypeIfNeeded()
        tokenLoadGeneration += 1
        let generation = tokenLoadGeneration
        guard validateTokenIdInput(), let tokenId = try? validTokenId() else { return }
        let recognitionTask = record.contractType == .generic ? contractTypeRecognitionTask : nil
        isLoadingToken = true
        tokenLoadError = nil
        tokenNoLongerExists = false
        Task { [weak self] in
            guard let self else { return }
            do {
                if let recognitionTask {
                    _ = await recognitionTask.value
                }
                guard self.isContractTypeResolved else {
                    throw SRC721ValidationError.invalidAddress("safe_zone.src721.type.unknown".localized)
                }
                guard let account = Web3Core.EthereumAddress(service.userAddress) else {
                    throw SRC721ValidationError.invalidAddress("safe_zone.src721.field.wallet".localized)
                }
                let state = try await service.tokenState(
                    type: contractType,
                    tokenId: tokenId,
                    account: account,
                    includeTokenURI: loadsTokenURI
                )
                await MainActor.run {
                    guard self.tokenLoadGeneration == generation else { return }
                    self.tokenState = state
                    self.isLoadingToken = false
                    self.tokenLoadError = nil
                    self.tokenNoLongerExists = false
                    self.operationMessage = nil
                    self.operationHashes = []
                }
            } catch {
                await MainActor.run {
                    guard self.tokenLoadGeneration == generation else { return }
                    self.isLoadingToken = false
                    if let validationError = error as? SRC721ValidationError,
                       validationError.isTokenNoLongerExists {
                        self.tokenNoLongerExists = true
                        self.tokenLoadError = nil
                    } else {
                        self.tokenNoLongerExists = false
                        self.tokenLoadError = error.localizedDescription
                    }
                    if showError, !self.tokenNoLongerExists {
                        self.showOperationError(error.localizedDescription)
                    }
                    self.tokenState = nil
                }
            }
        }
    }

    func loadToken(tokenId: BigUInt, showError: Bool = true) {
        self.tokenId = tokenId.description
        loadToken(showError: showError)
    }

    var canTransferLoadedToken: Bool {
        guard isContractTypeResolved, !isLoadingToken, let tokenState else { return false }
        return SRC721TokenAuthorization(
            tokenId: tokenState.tokenId,
            ownerAddress: tokenState.ownerAddress,
            approvedAddress: tokenState.approvedAddress,
            isApprovedForAll: tokenState.isApprovedForAll
        ).isAuthorized(for: service.userAddress)
    }

    var canApproveLoadedToken: Bool {
        guard isContractTypeResolved, !isLoadingToken, let tokenState else { return false }
        return isLoadedTokenOwner || tokenState.isApprovedForAll
    }

    var canBurnLoadedToken: Bool {
        contractType.canBurn && canTransferLoadedToken
    }

    private var isLoadedTokenOwner: Bool {
        tokenState?.ownerAddress.lowercased() == service.userAddress.lowercased()
    }

    func mint(to address: String, amount: String, admin: Bool) {
        guard validateMint(to: address, amount: amount, admin: admin) else { return }
        guard let mintAmount = try? SRC721Validation.amount(amount, field: "safe_zone.src721.field.amount".localized) else { return }
        guard isContractTypeResolved else {
            showOperationError("safe_zone.src721.type.unknown".localized)
            return
        }
        let type = contractType
        let operationName = (admin ? "safe_zone.src721.action.admin_mint" : "safe_zone.src721.action.mint").localized
        perform(operationName: operationName, operationKind: .mint, pendingMintAmount: mintAmount) { [service] in
            let recipient = try SRC721Validation.address(address, field: "safe_zone.src721.field.recipient".localized)
            if admin {
                return try await service.adminMint(type: type, to: recipient, amount: mintAmount)
            }
            return try await service.mint(type: type, to: recipient, amount: mintAmount)
        }
    }

    func burn(tokenId rawValue: String, onResolved: ((Bool) -> Void)? = nil) {
        guard contractType.canBurn else {
            showOperationError("safe_zone.src721.type.burnable".localized)
            return
        }
        let tokenId: BigUInt
        do {
            tokenId = try SRC721Validation.amount(rawValue, field: "safe_zone.src721.field.token_id".localized, allowZero: true)
        } catch {
            showOperationError(error.localizedDescription)
            return
        }
        self.tokenId = tokenId.description
        let burnType = contractType
        perform(operationName: "safe_zone.src721.action.burn".localized, operationKind: .burn, onConfirmed: { [weak self] in
            self?.burnedTokenId = tokenId
        }, onResolved: onResolved) { [service] in
            try await service.burn(type: burnType, tokenId: tokenId)
        }
    }

    func setBaseURI(_ value: String) {
        guard canManage else { showOperationError("safe_zone.src721.error.owner_required".localized); return }
        let type = contractType
        perform(operationName: "safe_zone.src721.action.update_all".localized) { [service] in try await service.setBaseURI(type: type, value: try SRC721Validation.baseURI(value)) }
    }

    func setMaxSupply(_ value: String) {
        guard canManage else { showOperationError("safe_zone.src721.error.owner_required".localized); return }
        let type = contractType
        perform(operationName: "safe_zone.src721.action.update_all".localized) { [service] in try await service.setMaxSupply(type: type, value: try SRC721Validation.amount(value, field: "safe_zone.src721.field.max_supply".localized)) }
    }

    func setMintPrice(_ value: String) {
        guard canManage else { showOperationError("safe_zone.src721.error.owner_required".localized); return }
        let type = contractType
        perform(operationName: "safe_zone.src721.action.update_all".localized) { [service] in try await service.setMintPrice(type: type, value: try SRC721Validation.amount(value, field: "safe_zone.src721.field.mint_price".localized, allowZero: true)) }
    }

    func updateParameters(baseURI: String, maxSupply: String, mintPrice: String) {
        guard canManage else { showOperationError("safe_zone.src721.error.owner_required".localized); return }
        let type = contractType
        perform(operationName: "safe_zone.src721.action.update_all".localized) { [service] in
            let baseURI = baseURI.trimmingCharacters(in: .whitespacesAndNewlines)
            let maxSupplyValue = try SRC721Validation.amount(maxSupply, field: "safe_zone.src721.field.max_supply".localized)
            let mintPriceValue = try SRC721Validation.amount(mintPrice, field: "safe_zone.src721.field.mint_price".localized, allowZero: true)
            return try await service.updateParameters(
                type: type,
                baseURI: baseURI.isEmpty ? nil : try SRC721Validation.baseURI(baseURI),
                maxSupply: maxSupplyValue,
                mintPrice: mintPriceValue
            )
        }
    }

    func updateAll(
        baseURI: String,
        maxSupply: String,
        mintPrice: String,
        orgName: String,
        description: String,
        officialURL: String,
        whitePaperURL: String,
        logo: Data?
    ) {
        guard canManage else { showOperationError("safe_zone.src721.error.owner_required".localized); return }
        guard validateUpdate(
            baseURI: baseURI,
            maxSupply: maxSupply,
            mintPrice: mintPrice,
            orgName: orgName,
            description: description,
            officialURL: officialURL,
            whitePaperURL: whitePaperURL,
            logo: logo
        ) else { return }

        let current = contractState
        let normalizedBaseURI = baseURI.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedOrgName = orgName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedOfficialURL = officialURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedWhitePaperURL = whitePaperURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURIValue = normalizedBaseURI == current?.baseURI ? nil : normalizedBaseURI
        let maxSupplyValue = BigUInt(maxSupply) == current?.maxSupply ? nil : BigUInt(maxSupply)
        let mintPriceValue = BigUInt(mintPrice) == current?.mintPrice ? nil : BigUInt(mintPrice)
        let metadata = (
            orgName: normalizedOrgName == current?.orgName ? nil : normalizedOrgName,
            description: normalizedDescription == current?.description ? nil : normalizedDescription,
            officialURL: normalizedOfficialURL == current?.officialURL ? nil : normalizedOfficialURL,
            whitePaperURL: normalizedWhitePaperURL == current?.whitePaperURL ? nil : normalizedWhitePaperURL
        )

        let type = contractType
        perform(operationName: "safe_zone.src721.action.update_all".localized) { [service] in
            try await service.updateAll(
                type: type,
                baseURI: baseURIValue,
                maxSupply: maxSupplyValue,
                mintPrice: mintPriceValue,
                allowList: nil,
                orgName: metadata.orgName,
                description: metadata.description,
                officialURL: metadata.officialURL,
                whitePaperURL: metadata.whitePaperURL,
                logo: logo
            )
        }
    }

    func updateDescription(_ value: String) {
        guard canManage else { showOperationError("safe_zone.src721.error.owner_required".localized); return }
        performMetadata(description: value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func updateOfficialURL(_ value: String) {
        guard canManage else { showOperationError("safe_zone.src721.error.owner_required".localized); return }
        performMetadata(officialURL: value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func updateWhitePaperURL(_ value: String) {
        guard canManage else { showOperationError("safe_zone.src721.error.owner_required".localized); return }
        performMetadata(whitePaperURL: value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func updateLogo(_ data: Data) {
        guard canManage else { showOperationError("safe_zone.src721.error.owner_required".localized); return }
        do {
            performMetadata(logo: try SRC721Validation.logo(data))
        } catch {
            showOperationError(error.localizedDescription)
        }
    }

    func updateOrgName(_ value: String) {
        guard canManage else { showOperationError("safe_zone.src721.error.owner_required".localized); return }
        performMetadata(orgName: value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func withdraw() {
        guard canManage else { showOperationError("safe_zone.src721.error.owner_required".localized); return }
        let type = contractType
        perform(operationName: "safe_zone.src721.action.withdraw".localized) { [service] in try await service.withdraw(type: type) }
    }

    func approve(to address: String) {
        guard validateTokenOperation(recipient: address, allowZeroRecipient: true) else { return }
        guard canApproveLoadedToken else {
            showOperationError(SRC721ValidationError.tokenOperationUnavailable.localizedDescription)
            return
        }
        let type = contractType
        perform(operationName: "safe_zone.src721.action.approve".localized) { [service] in
            let tokenId = try self.validTokenId()
            let recipient = try SRC721Validation.address(address, field: "safe_zone.src721.field.recipient".localized, allowZero: true)
            return try await service.approve(type: type, to: recipient, tokenId: tokenId)
        }
    }

    func transfer(to address: String, onResolved: ((Bool) -> Void)? = nil) {
        guard validateTokenOperation(recipient: address, allowZeroRecipient: false) else { return }
        guard canTransferLoadedToken else {
            showOperationError(SRC721ValidationError.tokenOperationUnavailable.localizedDescription)
            return
        }
        let type = contractType
        perform(operationName: "safe_zone.src721.action.transfer".localized, operationKind: .transfer, onResolved: onResolved) { [service] in
            let tokenId = try self.validTokenId()
            let recipient = try SRC721Validation.address(address, field: "safe_zone.src721.field.recipient".localized)
            guard let tokenState = self.tokenState, tokenState.tokenId == tokenId else {
                throw SRC721ValidationError.emptyField("safe_zone.src721.field.token_id".localized)
            }
            let sender = try SRC721Validation.address(tokenState.ownerAddress, field: "safe_zone.src721.field.owner".localized)
            return try await service.transfer(type: type, from: sender, to: recipient, tokenId: tokenId)
        }
    }

    func burn(onResolved: ((Bool) -> Void)? = nil) {
        guard validateTokenIdInput() else { return }
        guard canBurnLoadedToken else {
            showOperationError(SRC721ValidationError.tokenOperationUnavailable.localizedDescription)
            return
        }
        guard let tokenId = try? validTokenId() else { return }
        let burnType = contractType
        perform(operationName: "safe_zone.src721.action.burn".localized, operationKind: .burn, onConfirmed: { [weak self] in
            self?.burnedTokenId = tokenId
        }, onResolved: onResolved) { [service] in
            try await service.burn(type: burnType, tokenId: tokenId)
        }
    }

    private func validTokenId() throws -> BigUInt {
        do {
            return try SRC721Validation.amount(tokenId, field: "safe_zone.src721.field.token_id".localized, allowZero: true)
        } catch {
            throw SRC721ValidationError.invalidTokenId
        }
    }

    func validateMintSupplyInput(_ rawAmount: String) {
        mintAmountCautionState = .none
        guard !rawAmount.isEmpty,
              contractState != nil,
              let amount = try? SRC721Validation.amount(rawAmount, field: "safe_zone.src721.field.amount".localized) else {
            return
        }
        do {
            try SRC721Validation.validateMintSupply(remainSupply: remainingSupply, amount: amount)
        } catch {
            mintAmountCautionState = caution(for: error)
        }
    }

    func validateMint(to address: String, amount: String, admin: Bool) -> Bool {
        beginValidation()
        mintRecipientCautionState = .none
        mintAmountCautionState = .none
        if admin && !canManage {
            showOperationError("safe_zone.src721.error.owner_required".localized)
            return false
        }

        var isValid = true
        do { _ = try SRC721Validation.address(address, field: "safe_zone.src721.field.recipient".localized) }
        catch { setCaution(caution(for: error), for: .mintRecipient); isValid = false }
        var parsedAmount: BigUInt?
        do {
            parsedAmount = try SRC721Validation.amount(amount, field: "safe_zone.src721.field.amount".localized)
        }
        catch {
            parsedAmount = nil
            setCaution(caution(for: error), for: .mintAmount)
            isValid = false
        }

        guard let parsedAmount else { return isValid }
        guard let state = contractState else {
            setCaution(caution(for: SRC721ValidationError.contractStateUnavailable), for: .mintAmount)
            return false
        }
        do {
            try SRC721Validation.validateMintSupply(remainSupply: remainingSupply, amount: parsedAmount)
        } catch {
            setCaution(caution(for: error), for: .mintAmount)
            isValid = false
        }
        return isValid
    }

    func validateTokenIdInput() -> Bool {
        beginValidation()
        tokenIdCautionState = .none
        do {
            _ = try validTokenId()
            return true
        } catch {
            setCaution(caution(for: error), for: .tokenId)
            return false
        }
    }

    func validateTokenOperation(recipient: String, allowZeroRecipient: Bool) -> Bool {
        beginValidation()
        tokenIdCautionState = .none
        tokenRecipientCautionState = .none
        var isValid = true
        do { _ = try validTokenId() }
        catch { setCaution(caution(for: error), for: .tokenId); isValid = false }
        do { _ = try SRC721Validation.address(recipient, field: "safe_zone.src721.field.recipient".localized, allowZero: allowZeroRecipient) }
        catch { setCaution(caution(for: error), for: .tokenRecipient); isValid = false }
        return isValid
    }

    func setApprovalForAll(operatorAddress address: String, approved: Bool) {
        beginValidation()
        operatorCautionState = .none
        do {
            let operatorAddress = try SRC721Validation.address(address, field: "safe_zone.src721.field.address".localized)
            let operationName = (approved ? "safe_zone.src721.action.approve_all" : "safe_zone.src721.action.revoke_all").localized
            perform(operationName: operationName) { [service] in try await service.setApprovalForAll(operatorAddress: operatorAddress, approved: approved) }
        } catch {
            setCaution(caution(for: error), for: .operatorAddress)
        }
    }

    @MainActor
    private func validateUpdate(
        baseURI: String,
        maxSupply: String,
        mintPrice: String,
        orgName: String,
        description: String,
        officialURL: String,
        whitePaperURL: String,
        logo: Data?
    ) -> Bool {
        beginValidation()
        clearUpdateCautions()
        var isValid = true

        do { _ = try SRC721Validation.optionalBaseURI(baseURI) }
        catch { setCaution(caution(for: error), for: .baseURI); isValid = false }
        do { _ = try SRC721Validation.amount(maxSupply, field: "safe_zone.src721.field.max_supply".localized) }
        catch { setCaution(caution(for: error), for: .maxSupply); isValid = false }
        if let maximum = BigUInt(maxSupply), let current = contractState, maximum < current.totalSupply {
            setCaution(caution(for: SRC721ValidationError.invalidAmount("safe_zone.src721.field.max_supply".localized)), for: .maxSupply)
            isValid = false
        }
        do { _ = try SRC721Validation.amount(mintPrice, field: "safe_zone.src721.field.mint_price".localized, allowZero: true) }
        catch { setCaution(caution(for: error), for: .mintPrice); isValid = false }

        if let logo {
            do { _ = try SRC721Validation.logo(logo) }
            catch { setCaution(caution(for: error), for: .logo); isValid = false }
        }
        return isValid
    }

    private func clearUpdateCautions() {
        baseURICautionState = .none
        maxSupplyCautionState = .none
        mintPriceCautionState = .none
        orgNameCautionState = .none
        descriptionCautionState = .none
        officialURLCautionState = .none
        whitePaperURLCautionState = .none
        logoCautionState = .none
    }

    private func beginValidation() {
        invalidField = nil
    }

    private func setCaution(_ caution: CautionState, for field: SRC721DetailField) {
        switch field {
        case .mintRecipient: mintRecipientCautionState = caution
        case .mintAmount: mintAmountCautionState = caution
        case .baseURI: baseURICautionState = caution
        case .maxSupply: maxSupplyCautionState = caution
        case .mintPrice: mintPriceCautionState = caution
        case .orgName: orgNameCautionState = caution
        case .description: descriptionCautionState = caution
        case .officialURL: officialURLCautionState = caution
        case .whitePaperURL: whitePaperURLCautionState = caution
        case .logo: logoCautionState = caution
        case .tokenId: tokenIdCautionState = caution
        case .tokenRecipient: tokenRecipientCautionState = caution
        case .operatorAddress: operatorCautionState = caution
        }
        if invalidField == nil {
            invalidField = field
            validationRequestID = UUID()
        }
    }

    private func caution(for error: Error) -> CautionState {
        .caution(Caution(text: error.localizedDescription, type: .error))
    }

    private func perform(operationName: String, operationKind: SRC721TransactionOperation? = nil, pendingMintAmount: BigUInt? = nil, onConfirmed: (() -> Void)? = nil, onResolved: ((Bool) -> Void)? = nil, _ operation: @escaping () async throws -> String) {
        perform(operationName: operationName, operationKind: operationKind, pendingMintAmount: pendingMintAmount, onConfirmed: onConfirmed, onResolved: onResolved) { [operation] in [try await operation()] }
    }

    private func perform(operationName: String, operationKind: SRC721TransactionOperation? = nil, pendingMintAmount: BigUInt? = nil, onConfirmed: (() -> Void)? = nil, onResolved: ((Bool) -> Void)? = nil, _ operation: @escaping () async throws -> [String]) {
        guard operationState != .sending else { return }
        operationState = .sending
        isSubmittingOperation = true
        operationMessage = nil
        operationHashes = []
        Task { [weak self] in
            guard let self else { return }
            do {
                let hashes = try await operation()
                guard !hashes.isEmpty else { throw Web3Error.processingError(desc: "No transaction generated") }
                self.operationHashes = hashes
                let allSucceeded = await trackTransactions(hashes, operationName: operationName, operationKind: operationKind, pendingMintAmount: pendingMintAmount)
                await MainActor.run {
                    self.operationState = allSucceeded ? .completed : .failed
                    self.operationMessage = allSucceeded
                        ? "safe_zone.src721.operation.confirmed".localized
                        : "safe_zone.src721.error.transaction".localized
                    self.operationHashes = hashes
                    if allSucceeded {
                        onConfirmed?()
                    }
                    onResolved?(allSucceeded)
                    self.refresh()
                }
            } catch let batchError as SRC721BatchOperationError {
                _ = await trackTransactions(batchError.submittedHashes, operationName: operationName, operationKind: operationKind, pendingMintAmount: pendingMintAmount)
                await MainActor.run {
                    self.isSubmittingOperation = false
                    self.operationState = .failed
                    self.operationMessage = self.localizedOperationError(for: batchError.underlying)
                    self.operationHashes = batchError.submittedHashes
                    onResolved?(false)
                    self.refresh()
                }
            } catch {
                await MainActor.run {
                    self.isSubmittingOperation = false
                    self.operationState = .failed
                    self.operationMessage = self.localizedOperationError(for: error)
                    onResolved?(false)
                }
            }
        }
    }

    private func localizedOperationError(for error: Error) -> String {
        let description = "\(error) \(error.localizedDescription)".lowercased()
        if description.contains("transfer to non erc721receiver implementer") {
            return "safe_zone.src721.error.unsupported_nft_recipient".localized
        }
        return error.localizedDescription
    }

    private func trackTransactions(_ hashes: [String], operationName: String, operationKind: SRC721TransactionOperation? = nil, pendingMintAmount: BigUInt? = nil) async -> Bool {
        var allSucceeded = true
        for (index, hash) in hashes.enumerated() {
            let transactionID = UUID()
            let createdAt = Date()
            let tokenId = self.tokenId.isEmpty ? nil : self.tokenId
            self.storage.save(transaction: SRC721TransactionRecord(
                id: transactionID, accountId: self.record.accountId, chainId: self.record.chainId,
                walletAddress: self.record.walletAddress, contractAddress: self.record.contractAddress,
                operation: operationName, operationKind: operationKind, tokenId: tokenId, amount: pendingMintAmount?.description, transactionHash: hash, status: .pending,
                errorMessage: nil, createdAt: createdAt
            ))
            if index == 0 {
                await MainActor.run {
                    self.isSubmittingOperation = false
                    self.submissionID = UUID()
                }
            }

            do {
                let success = try await self.service.waitForTransaction(hash)
                self.storage.save(transaction: SRC721TransactionRecord(
                    id: transactionID, accountId: self.record.accountId, chainId: self.record.chainId,
                    walletAddress: self.record.walletAddress, contractAddress: self.record.contractAddress,
                    operation: operationName, operationKind: operationKind, tokenId: tokenId, amount: pendingMintAmount?.description, transactionHash: hash,
                    status: success ? .confirmed : .failed,
                    errorMessage: success ? nil : "safe_zone.src721.error.transaction".localized,
                    createdAt: createdAt
                ))
                allSucceeded = allSucceeded && success
            } catch SRC721ValidationError.transactionTimeout {
                allSucceeded = false
            } catch {
                // Keep pending when the receipt result is uncertain; refresh can retry it.
                allSucceeded = false
            }
        }
        return allSucceeded
    }

    private func performMetadata(orgName: String? = nil, description: String? = nil, officialURL: String? = nil, whitePaperURL: String? = nil, logo: Data? = nil) {
        let values = [orgName, description, officialURL, whitePaperURL].compactMap { $0 }
        guard logo != nil || values.contains(where: { !$0.isEmpty }) else {
            showOperationError(SRC721ValidationError.emptyField("safe_zone.src721.field.value".localized).localizedDescription)
            return
        }
        let type = contractType
        perform(operationName: "safe_zone.src721.action.update_all".localized) { [service] in
            let hashes = try await service.updateMetadata(type: type, orgName: orgName, description: description, officialURL: officialURL, whitePaperURL: whitePaperURL, logo: logo)
            return hashes
        }
    }

    private func showOperationError(_ message: String) {
        operationState = .failed
        operationMessage = message
        operationHashes = []
    }

    private func updateStoredOwner(_ owner: String) {
        guard record.currentOwnerAddress?.lowercased() != owner.lowercased() else { return }
        var updated = record
        updated.currentOwnerAddress = owner
        storage.update(contract: updated)
    }
}

@MainActor
final class SRC721LogoViewModel: ObservableObject {
    let record: SRC721ContractRecord
    let type: SRC721ContractType
    private let service: SRC721Service
    @Published var selectedImage: UIImage? {
        didSet { updateLogoData() }
    }
    @Published private(set) var fee: Decimal?
    @Published private(set) var logoData: Data?
    @Published var logoCautionState: CautionState = .none
    @Published private(set) var sendState: SRC721LogoSendState = .idle
    @Published private(set) var operationError: String?

    init(record: SRC721ContractRecord, type: SRC721ContractType, currentLogo: Data, service: SRC721Service) {
        self.record = record
        self.type = type
        self.service = service
        selectedImage = UIImage(data: currentLogo)
        loadFee()
    }

    private func loadFee() {
        Task {
            fee = try? await service.logoPayAmount(type: type).safe4ToDecimal()
        }
    }

    private func updateLogoData() {
        guard let selectedImage else {
            logoData = nil
            logoCautionState = .none
            sendState = .idle
            return
        }
        guard let data = Self.logoData(from: selectedImage) else {
            logoData = nil
            logoCautionState = .caution(Caution(text: "safe_zone.src721.error.logo".localized, type: .error))
            sendState = .idle
            return
        }
        logoData = data
        logoCautionState = .none
        operationError = nil
        sendState = .ready
    }

    func upload(onComplete: @escaping (SRC721LogoSendState) -> Void) {
        guard let logoData else {
            logoCautionState = .caution(Caution(text: "safe_zone.src721.error.logo_required".localized, type: .error))
            return
        }
        sendState = .sending
        operationError = nil
        Task {
            do {
                let hashes = try await service.updateMetadata(
                    type: type,
                    orgName: nil,
                    description: nil,
                    officialURL: nil,
                    whitePaperURL: nil,
                    logo: logoData
                )
                guard !hashes.isEmpty else { throw Web3Error.processingError(desc: "No transaction generated") }
                sendState = .completed
                onComplete(.completed)
            } catch {
                operationError = error.localizedDescription
                sendState = .failed
                onComplete(.failed)
            }
        }
    }

    private static func logoData(from image: UIImage) -> Data? {
        let maxBytes = 128 * 1024
        if let png = image.pngData(), png.count <= maxBytes { return png }
        var quality: CGFloat = 0.9
        while quality >= 0.2 {
            if let data = image.jpegData(compressionQuality: quality), data.count <= maxBytes { return data }
            quality -= 0.1
        }
        return nil
    }
}

enum SRC721LogoSendState: Equatable {
    case idle
    case ready
    case sending
    case completed
    case failed
}

enum SRC721AsyncState: Equatable {
    case idle
    case sending
    case completed
    case failed
}

enum SRC721DataState: Equatable {
    case loading
    case completed
    case unavailable(String)
    case failed(String)
}
