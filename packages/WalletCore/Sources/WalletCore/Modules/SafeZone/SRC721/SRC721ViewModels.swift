import BigInt
import Combine
import Foundation
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
            _ = try SRC721Validation.amount(mintPrice, field: "safe_zone.src721.field.mint_price".localized, allowZero: true)
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
                let mintPrice = try SRC721Validation.amount(mintPrice, field: "safe_zone.src721.field.mint_price".localized, allowZero: true)
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
    let service: SRC721Service
    let storage: SRC721Storage
    let accountId: String
    let walletAddress: String

    @Published private(set) var records: [SRC721ContractRecord] = []
    @Published private(set) var isRefreshing = false

    init(service: SRC721Service, storage: SRC721Storage, accountId: String, walletAddress: String) {
        self.service = service
        self.storage = storage
        self.accountId = accountId
        self.walletAddress = walletAddress
        reload()
    }

    func reload() {
        records = storage.contracts(accountId: accountId, chainId: service.chainId, walletAddress: walletAddress)
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task { [weak self] in
            guard let self else { return }
            let currentRecords = records
            for record in currentRecords {
                if record.transactionStatus == .pending, let hash = record.deployTransactionHash {
                    do {
                        let success = try await service.waitForTransaction(hash)
                        var updated = record
                        updated.transactionStatus = success ? .confirmed : .failed
                        if success, let deployedAddress = try? await service.deployedContractAddress(for: hash) {
                            updated.contractAddress = deployedAddress
                        }
                        storage.update(contract: updated)
                    } catch SRC721ValidationError.transactionTimeout {
                        continue
                    } catch {
                        continue
                    }
                    continue
                }
                guard record.transactionStatus == .confirmed, record.contractType != .unknown else { continue }
                let contractService = service.binding(contractAddress: record.contractAddress)
                guard let state = try? await contractService.state(type: record.contractType) else { continue }
                var updated = record
                updated.name = state.name
                updated.symbol = state.symbol
                updated.baseURI = state.baseURI
                updated.maxSupply = state.maxSupply.description
                updated.mintPrice = state.mintPrice.description
                updated.currentOwnerAddress = state.ownerAddress
                storage.update(contract: updated)
            }

            for transaction in storage.transactions(accountId: accountId, chainId: service.chainId, walletAddress: walletAddress) where transaction.status == .pending {
                do {
                    let success = try await service.waitForTransaction(transaction.transactionHash)
                    var updated = transaction
                    updated.status = success ? .confirmed : .failed
                    updated.errorMessage = success ? nil : "safe_zone.src721.error.transaction".localized
                    storage.save(transaction: updated)
                } catch SRC721ValidationError.transactionTimeout {
                    continue
                } catch {
                    continue
                }
            }
            await MainActor.run {
                self.reload()
                self.isRefreshing = false
            }
        }
    }
}

@MainActor
final class SRC721WalletAssetsViewModel: ObservableObject {
    private static let pageSize = 50
    private static let maximumTokensPerContract = 500

    private let service: SRC721Service
    private let storage: SRC721Storage
    private let accountId: String
    private let walletAddress: String

    @Published private(set) var assets: [SRC721WalletAsset] = []
    @Published private(set) var collections: [SRC721WalletCollection] = []
    @Published private(set) var dataState: SRC721DataState = .loading
    @Published private(set) var isTruncated = false

    init(service: SRC721Service, storage: SRC721Storage, accountId: String, walletAddress: String) {
        self.service = service
        self.storage = storage
        self.accountId = accountId
        self.walletAddress = walletAddress
        refresh()
    }

    func refresh() {
        dataState = .loading
        isTruncated = false
        let records = storage.contracts(accountId: accountId, chainId: service.chainId, walletAddress: walletAddress)
            .filter { $0.transactionStatus == .confirmed && $0.contractType != .unknown }

        Task { [weak self] in
            guard let self else { return }
            var loadedAssets: [SRC721WalletAsset] = []
            var didLoadAnyContract = false
            var truncated = false

            for record in records {
                let provider = service.binding(contractAddress: record.contractAddress)
                var offset = 0
                var loadedCount = 0

                do {
                    while loadedCount < Self.maximumTokensPerContract {
                        let page = try await provider.ownedTokenPage(type: record.contractType, offset: offset, limit: Self.pageSize)
                        didLoadAnyContract = true
                        loadedAssets.append(contentsOf: page.tokens.map { SRC721WalletAsset(contract: record, token: $0) })
                        loadedCount += page.tokens.count
                        offset = try SRC721OwnedTokenPaging.nextOffset(
                            offset: offset,
                            total: page.total,
                            returnedCount: page.tokens.count,
                            limit: Self.pageSize
                        )
                        guard BigUInt(offset) < page.total else { break }
                    }
                    if loadedCount == Self.maximumTokensPerContract {
                        truncated = true
                    }
                } catch {
                    continue
                }
            }

            await MainActor.run {
                self.assets = loadedAssets
                self.collections = SRC721WalletCollection.grouped(assets: loadedAssets)
                self.isTruncated = truncated
                self.dataState = records.isEmpty || didLoadAnyContract ? .completed : .failed("safe_zone.src721.error.enumeration_unavailable".localized)
            }
        }
    }
}

@MainActor
final class SRC721AllowListViewModel: ObservableObject {
    let record: SRC721ContractRecord
    private let service: SRC721Service
    private let storage: SRC721Storage

    @Published private(set) var entries: [SRC721AllowListEntry] = []
    @Published private(set) var dataState: SRC721DataState = .loading
    @Published private(set) var isOwner = false
    @Published private(set) var operationState: SRC721AsyncState = .idle
    @Published var operationMessage: String?
    @Published private(set) var operationHashes: [String] = []
    @Published var address = ""
    @Published var amount = ""
    @Published var addressCautionState: CautionState = .none
    @Published var amountCautionState: CautionState = .none
    @Published private(set) var editingEntry: SRC721AllowListEntry?
    @Published private(set) var invalidField: SRC721AllowListEditorField?
    @Published private(set) var validationRequestID = UUID()

    var canTransact: Bool { service.canSign }

    init(record: SRC721ContractRecord, service: SRC721Service, storage: SRC721Storage) {
        self.record = record
        self.service = service
        self.storage = storage
        refresh()
    }

    func refresh() {
        entries = storage.allowListEntries(for: record)
        dataState = .loading
        Task { [weak self] in
            guard let self else { return }
            do {
                let state = try await service.state(type: record.contractType)
                await MainActor.run {
                    self.isOwner = state.ownerAddress.lowercased() == self.service.userAddress.lowercased()
                    self.dataState = .completed
                }
            } catch {
                await MainActor.run {
                    self.dataState = .failed(error.localizedDescription)
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
              let parsedAmount = try? SRC721Validation.amount(amount, field: "safe_zone.src721.field.amount".localized) else {
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
                    self.entries = storage.allowListEntries(for: record)
                    self.operationState = .completed
                }
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
            _ = try SRC721Validation.amount(amount, field: "safe_zone.src721.field.amount".localized)
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

    @Published private(set) var contractState: SRC721ContractState?
    @Published private(set) var tokenState: SRC721TokenState?
    @Published private(set) var isLoadingToken = false
    @Published private(set) var tokenLoadError: String?
    @Published private(set) var burnedTokenId: BigUInt?
    @Published private(set) var dataState: SRC721DataState = .loading
    @Published private(set) var operationState: SRC721AsyncState = .idle
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
        guard let owner = contractState?.ownerAddress else { return false }
        return owner.lowercased() == service.userAddress.lowercased()
    }

    var canTransact: Bool { service.canSign }

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

    init(record: SRC721ContractRecord, service: SRC721Service, storage: SRC721Storage) {
        self.record = record
        self.service = service
        self.storage = storage
        refresh()
    }

    func refresh() {
        refreshGeneration += 1
        let generation = refreshGeneration
        let isInitialLoad = contractState == nil
        if isInitialLoad {
            dataState = .loading
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                let state = try await service.state(type: record.contractType)
                await MainActor.run {
                    guard self.refreshGeneration == generation else { return }
                    self.contractState = state
                    self.dataState = .completed
                    self.updateStoredOwner(state.ownerAddress)
                }
            } catch {
                await MainActor.run {
                    guard self.refreshGeneration == generation else { return }
                    if isInitialLoad {
                        self.dataState = .failed(error.localizedDescription)
                    }
                }
            }
        }
    }

    func loadToken() {
        tokenLoadGeneration += 1
        let generation = tokenLoadGeneration
        guard validateTokenIdInput(), let tokenId = try? validTokenId() else { return }
        isLoadingToken = true
        tokenLoadError = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                guard let account = Web3Core.EthereumAddress(service.userAddress) else {
                    throw SRC721ValidationError.invalidAddress("safe_zone.src721.field.wallet".localized)
                }
                let state = try await service.tokenState(type: record.contractType, tokenId: tokenId, account: account)
                await MainActor.run {
                    guard self.tokenLoadGeneration == generation else { return }
                    self.tokenState = state
                    self.isLoadingToken = false
                    self.tokenLoadError = nil
                    self.operationMessage = nil
                    self.operationHashes = []
                }
            } catch {
                await MainActor.run {
                    guard self.tokenLoadGeneration == generation else { return }
                    self.isLoadingToken = false
                    self.tokenLoadError = error.localizedDescription
                    self.showOperationError(error.localizedDescription)
                    self.tokenState = nil
                }
            }
        }
    }

    func loadToken(tokenId: BigUInt) {
        self.tokenId = tokenId.description
        loadToken()
    }

    var canTransferLoadedToken: Bool {
        guard let tokenState else { return false }
        return isLoadedTokenOwner || isLoadedTokenApproved || tokenState.isApprovedForAll
    }

    var canApproveLoadedToken: Bool {
        guard let tokenState else { return false }
        return isLoadedTokenOwner || tokenState.isApprovedForAll
    }

    var canBurnLoadedToken: Bool {
        record.contractType.canBurn && canTransferLoadedToken
    }

    private var isLoadedTokenOwner: Bool {
        tokenState?.ownerAddress.lowercased() == service.userAddress.lowercased()
    }

    private var isLoadedTokenApproved: Bool {
        tokenState?.approvedAddress.lowercased() == service.userAddress.lowercased()
    }

    func mint(to address: String, amount: String, admin: Bool) {
        guard validateMint(to: address, amount: amount, admin: admin) else { return }
        let operationName = (admin ? "safe_zone.src721.action.admin_mint" : "safe_zone.src721.action.mint").localized
        perform(operationName: operationName) { [service, record] in
            let recipient = try SRC721Validation.address(address, field: "safe_zone.src721.field.recipient".localized)
            let amount = try SRC721Validation.amount(amount, field: "safe_zone.src721.field.amount".localized)
            if admin {
                return try await service.adminMint(type: record.contractType, to: recipient, amount: amount)
            }
            return try await service.mint(type: record.contractType, to: recipient, amount: amount)
        }
    }

    func setBaseURI(_ value: String) {
        guard canManage else { showOperationError("safe_zone.src721.error.owner_required".localized); return }
        perform(operationName: "safe_zone.src721.action.update_all".localized) { [service, record] in try await service.setBaseURI(type: record.contractType, value: try SRC721Validation.baseURI(value)) }
    }

    func setMaxSupply(_ value: String) {
        guard canManage else { showOperationError("safe_zone.src721.error.owner_required".localized); return }
        perform(operationName: "safe_zone.src721.action.update_all".localized) { [service, record] in try await service.setMaxSupply(type: record.contractType, value: try SRC721Validation.amount(value, field: "safe_zone.src721.field.max_supply".localized)) }
    }

    func setMintPrice(_ value: String) {
        guard canManage else { showOperationError("safe_zone.src721.error.owner_required".localized); return }
        perform(operationName: "safe_zone.src721.action.update_all".localized) { [service, record] in try await service.setMintPrice(type: record.contractType, value: try SRC721Validation.amount(value, field: "safe_zone.src721.field.mint_price".localized, allowZero: true)) }
    }

    func updateParameters(baseURI: String, maxSupply: String, mintPrice: String) {
        guard canManage else { showOperationError("safe_zone.src721.error.owner_required".localized); return }
        perform(operationName: "safe_zone.src721.action.update_all".localized) { [service, record] in
            let baseURI = baseURI.trimmingCharacters(in: .whitespacesAndNewlines)
            let maxSupplyValue = try SRC721Validation.amount(maxSupply, field: "safe_zone.src721.field.max_supply".localized)
            let mintPriceValue = try SRC721Validation.amount(mintPrice, field: "safe_zone.src721.field.mint_price".localized, allowZero: true)
            return try await service.updateParameters(
                type: record.contractType,
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

        perform(operationName: "safe_zone.src721.action.update_all".localized) { [service, record] in
            try await service.updateAll(
                type: record.contractType,
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
        perform(operationName: "safe_zone.src721.action.withdraw".localized) { [service, record] in try await service.withdraw(type: record.contractType) }
    }

    func approve(to address: String) {
        guard validateTokenOperation(recipient: address, allowZeroRecipient: true) else { return }
        guard canApproveLoadedToken else {
            showOperationError(SRC721ValidationError.tokenOperationUnavailable.localizedDescription)
            return
        }
        perform(operationName: "safe_zone.src721.action.approve".localized) { [service, record] in
            let tokenId = try self.validTokenId()
            let recipient = try SRC721Validation.address(address, field: "safe_zone.src721.field.recipient".localized, allowZero: true)
            return try await service.approve(type: record.contractType, to: recipient, tokenId: tokenId)
        }
    }

    func transfer(to address: String) {
        guard validateTokenOperation(recipient: address, allowZeroRecipient: false) else { return }
        guard canTransferLoadedToken else {
            showOperationError(SRC721ValidationError.tokenOperationUnavailable.localizedDescription)
            return
        }
        perform(operationName: "safe_zone.src721.action.transfer".localized) { [service, record] in
            let tokenId = try self.validTokenId()
            let recipient = try SRC721Validation.address(address, field: "safe_zone.src721.field.recipient".localized)
            guard let tokenState = self.tokenState, tokenState.tokenId == tokenId else {
                throw SRC721ValidationError.emptyField("safe_zone.src721.field.token_id".localized)
            }
            let sender = try SRC721Validation.address(tokenState.ownerAddress, field: "safe_zone.src721.field.owner".localized)
            return try await service.transfer(type: record.contractType, from: sender, to: recipient, tokenId: tokenId)
        }
    }

    func burn() {
        guard validateTokenIdInput() else { return }
        guard canBurnLoadedToken else {
            showOperationError(SRC721ValidationError.tokenOperationUnavailable.localizedDescription)
            return
        }
        guard let tokenId = try? validTokenId() else { return }
        perform(operationName: "safe_zone.src721.action.burn".localized, onConfirmed: { [weak self] in
            self?.burnedTokenId = tokenId
        }) { [service, record] in
            try await service.burn(type: record.contractType, tokenId: tokenId)
        }
    }

    private func validTokenId() throws -> BigUInt {
        do {
            return try SRC721Validation.amount(tokenId, field: "safe_zone.src721.field.token_id".localized, allowZero: true)
        } catch {
            throw SRC721ValidationError.invalidTokenId
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

        guard !admin, let parsedAmount else { return isValid }
        guard let state = contractState else {
            setCaution(caution(for: SRC721ValidationError.contractStateUnavailable), for: .mintAmount)
            return false
        }
        do {
            try SRC721Validation.validatePublicMint(state: state, amount: parsedAmount)
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

    private func perform(operationName: String, onConfirmed: (() -> Void)? = nil, _ operation: @escaping () async throws -> String) {
        perform(operationName: operationName, onConfirmed: onConfirmed) { [operation] in [try await operation()] }
    }

    private func perform(operationName: String, onConfirmed: (() -> Void)? = nil, _ operation: @escaping () async throws -> [String]) {
        guard operationState != .sending else { return }
        operationState = .sending
        operationMessage = nil
        operationHashes = []
        Task { [weak self] in
            guard let self else { return }
            do {
                let hashes = try await operation()
                guard !hashes.isEmpty else { throw Web3Error.processingError(desc: "No transaction generated") }
                let allSucceeded = await trackTransactions(hashes, operationName: operationName)
                await MainActor.run {
                    self.operationState = allSucceeded ? .completed : .failed
                    self.operationMessage = allSucceeded
                        ? "safe_zone.src721.operation.confirmed".localized
                        : "safe_zone.src721.error.transaction".localized
                    self.operationHashes = hashes
                    if allSucceeded {
                        onConfirmed?()
                    }
                    self.refresh()
                }
            } catch let batchError as SRC721BatchOperationError {
                _ = await trackTransactions(batchError.submittedHashes, operationName: operationName)
                await MainActor.run {
                    self.operationState = .failed
                    self.operationMessage = batchError.localizedDescription
                    self.operationHashes = batchError.submittedHashes
                    self.refresh()
                }
            } catch {
                await MainActor.run {
                    self.operationState = .failed
                    self.operationMessage = error.localizedDescription
                }
            }
        }
    }

    private func trackTransactions(_ hashes: [String], operationName: String) async -> Bool {
        var allSucceeded = true
        for hash in hashes {
            let transactionID = UUID()
            let createdAt = Date()
            let tokenId = self.tokenId.isEmpty ? nil : self.tokenId
            self.storage.save(transaction: SRC721TransactionRecord(
                id: transactionID, accountId: self.record.accountId, chainId: self.record.chainId,
                walletAddress: self.record.walletAddress, contractAddress: self.record.contractAddress,
                operation: operationName, tokenId: tokenId, transactionHash: hash, status: .pending,
                errorMessage: nil, createdAt: createdAt
            ))

            do {
                let success = try await self.service.waitForTransaction(hash)
                self.storage.save(transaction: SRC721TransactionRecord(
                    id: transactionID, accountId: self.record.accountId, chainId: self.record.chainId,
                    walletAddress: self.record.walletAddress, contractAddress: self.record.contractAddress,
                    operation: operationName, tokenId: tokenId, transactionHash: hash,
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
        perform(operationName: "safe_zone.src721.action.update_all".localized) { [service, record] in
            let hashes = try await service.updateMetadata(type: record.contractType, orgName: orgName, description: description, officialURL: officialURL, whitePaperURL: whitePaperURL, logo: logo)
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

enum SRC721AsyncState: Equatable {
    case idle
    case sending
    case completed
    case failed
}

enum SRC721DataState: Equatable {
    case loading
    case completed
    case failed(String)
}
