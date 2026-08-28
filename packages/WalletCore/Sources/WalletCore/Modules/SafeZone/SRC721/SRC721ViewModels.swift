import BigInt
import Combine
import Foundation
import Web3Core

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
        nameCautionState = .none
        symbolCautionState = .none
        baseURICautionState = .none
        maxSupplyCautionState = .none
        mintPriceCautionState = .none
    }

    private func setCaution(_ message: String, for field: DeployField) {
        let caution = CautionState.caution(Caution(text: message, type: .error))
        switch field {
        case .name: nameCautionState = caution
        case .symbol: symbolCautionState = caution
        case .baseURI: baseURICautionState = caution
        case .maxSupply: maxSupplyCautionState = caution
        case .mintPrice: mintPriceCautionState = caution
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
final class SRC721ImportViewModel: ObservableObject {
    private let service: SRC721Service
    private let storage: SRC721Storage
    private let accountId: String
    private let walletAddress: String

    @Published var address = ""
    @Published var type: SRC721ContractType = .standard
    @Published var state: SRC721AsyncState = .idle
    @Published var errorMessage: String?

    init(service: SRC721Service, storage: SRC721Storage, accountId: String, walletAddress: String) {
        self.service = service
        self.storage = storage
        self.accountId = accountId
        self.walletAddress = walletAddress
    }

    func importContract() {
        guard state != .sending else { return }
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
    @Published private(set) var dataState: SRC721DataState = .loading
    @Published private(set) var operationState: SRC721AsyncState = .idle
    @Published var operationMessage: String?
    @Published var tokenId = ""
    @Published var baseURICautionState: CautionState = .none
    @Published var maxSupplyCautionState: CautionState = .none
    @Published var mintPriceCautionState: CautionState = .none
    @Published var allowListCautionState: CautionState = .none
    @Published var orgNameCautionState: CautionState = .none
    @Published var descriptionCautionState: CautionState = .none
    @Published var officialURLCautionState: CautionState = .none
    @Published var whitePaperURLCautionState: CautionState = .none
    @Published var logoCautionState: CautionState = .none

    var canManage: Bool {
        guard let owner = contractState?.ownerAddress else { return false }
        return owner.lowercased() == service.userAddress.lowercased()
    }

    var canTransact: Bool { service.canSign }

    func hasUpdateChanges(
        baseURI: String,
        maxSupply: String,
        mintPrice: String,
        allowListAddresses: String,
        allowListAmounts: String,
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
            !allowListAddresses.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !allowListAmounts.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            trimmedOrgName != current.orgName ||
            trimmedDescription != current.description ||
            trimmedOfficialURL != current.officialURL ||
            trimmedWhitePaperURL != current.whitePaperURL ||
            logo != nil
    }

    init(record: SRC721ContractRecord, service: SRC721Service, storage: SRC721Storage) {
        self.record = record
        self.service = service
        self.storage = storage
        refresh()
    }

    func refresh() {
        dataState = .loading
        Task { [weak self] in
            guard let self else { return }
            do {
                let state = try await service.state(type: record.contractType)
                await MainActor.run {
                    self.contractState = state
                    self.dataState = .completed
                    self.updateStoredOwner(state.ownerAddress)
                }
            } catch {
                await MainActor.run {
                    self.dataState = .failed(error.localizedDescription)
                }
            }
        }
    }

    func loadToken() {
        guard let tokenId = BigUInt(tokenId), tokenId >= 0 else {
            operationMessage = SRC721ValidationError.invalidTokenId.localizedDescription
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                let state = try await service.tokenState(type: record.contractType, tokenId: tokenId)
                await MainActor.run { self.tokenState = state; self.operationMessage = nil }
            } catch {
                await MainActor.run { self.operationMessage = error.localizedDescription; self.tokenState = nil }
            }
        }
    }

    func mint(to address: String, amount: String, admin: Bool) {
        let currentMintPrice = contractState?.mintPrice ?? 0
        if admin && !canManage {
            operationMessage = "safe_zone.src721.error.owner_required".localized
            return
        }
        perform { [service, record] in
            let recipient = try SRC721Validation.address(address, field: "safe_zone.src721.field.recipient".localized)
            let amount = try SRC721Validation.amount(amount, field: "safe_zone.src721.field.amount".localized)
            if admin {
                return try await service.adminMint(type: record.contractType, to: recipient, amount: amount)
            }
            return try await service.mint(type: record.contractType, to: recipient, amount: amount, mintPrice: currentMintPrice)
        }
    }

    func setBaseURI(_ value: String) {
        guard canManage else { operationMessage = "safe_zone.src721.error.owner_required".localized; return }
        perform { [service, record] in try await service.setBaseURI(type: record.contractType, value: try SRC721Validation.baseURI(value)) }
    }

    func setMaxSupply(_ value: String) {
        guard canManage else { operationMessage = "safe_zone.src721.error.owner_required".localized; return }
        perform { [service, record] in try await service.setMaxSupply(type: record.contractType, value: try SRC721Validation.amount(value, field: "safe_zone.src721.field.max_supply".localized)) }
    }

    func setMintPrice(_ value: String) {
        guard canManage else { operationMessage = "safe_zone.src721.error.owner_required".localized; return }
        perform { [service, record] in try await service.setMintPrice(type: record.contractType, value: try SRC721Validation.amount(value, field: "safe_zone.src721.field.mint_price".localized, allowZero: true)) }
    }

    func updateParameters(baseURI: String, maxSupply: String, mintPrice: String) {
        guard canManage else { operationMessage = "safe_zone.src721.error.owner_required".localized; return }
        perform { [service, record] in
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
        allowListAddresses: String,
        allowListAmounts: String,
        orgName: String,
        description: String,
        officialURL: String,
        whitePaperURL: String,
        logo: Data?
    ) {
        guard canManage else { operationMessage = "safe_zone.src721.error.owner_required".localized; return }
        guard validateUpdate(
            baseURI: baseURI,
            maxSupply: maxSupply,
            mintPrice: mintPrice,
            allowListAddresses: allowListAddresses,
            allowListAmounts: allowListAmounts,
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
        let allowList: ([Web3Core.EthereumAddress], [BigUInt])?
        if allowListAddresses.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && allowListAmounts.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            allowList = nil
        } else {
            do {
                allowList = try SRC721Validation.allowList(addresses: allowListAddresses, amounts: allowListAmounts)
            } catch {
                return
            }
        }

        perform { [service, record] in
            try await service.updateAll(
                type: record.contractType,
                baseURI: baseURIValue,
                maxSupply: maxSupplyValue,
                mintPrice: mintPriceValue,
                allowList: allowList,
                orgName: metadata.orgName,
                description: metadata.description,
                officialURL: metadata.officialURL,
                whitePaperURL: metadata.whitePaperURL,
                logo: logo
            )
        }
    }

    func setAllowList(addresses: String, amounts: String) {
        guard canManage else { operationMessage = "safe_zone.src721.error.owner_required".localized; return }
        perform { [service, record] in
            let list = try SRC721Validation.allowList(addresses: addresses, amounts: amounts)
            return try await service.setAllowList(type: record.contractType, addresses: list.0, amounts: list.1)
        }
    }

    func updateDescription(_ value: String) {
        guard canManage else { operationMessage = "safe_zone.src721.error.owner_required".localized; return }
        performMetadata(description: value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func updateOfficialURL(_ value: String) {
        guard canManage else { operationMessage = "safe_zone.src721.error.owner_required".localized; return }
        performMetadata(officialURL: value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func updateWhitePaperURL(_ value: String) {
        guard canManage else { operationMessage = "safe_zone.src721.error.owner_required".localized; return }
        performMetadata(whitePaperURL: value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func updateLogo(_ data: Data) {
        guard canManage else { operationMessage = "safe_zone.src721.error.owner_required".localized; return }
        do {
            performMetadata(logo: try SRC721Validation.logo(data))
        } catch {
            operationMessage = error.localizedDescription
        }
    }

    func updateOrgName(_ value: String) {
        guard canManage else { operationMessage = "safe_zone.src721.error.owner_required".localized; return }
        performMetadata(orgName: value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func withdraw() {
        guard canManage else { operationMessage = "safe_zone.src721.error.owner_required".localized; return }
        perform { [service, record] in try await service.withdraw(type: record.contractType) }
    }

    func approve(to address: String) {
        perform { [service, record] in
            let tokenId = try self.validTokenId()
            let recipient = try SRC721Validation.address(address, field: "safe_zone.src721.field.recipient".localized, allowZero: true)
            return try await service.approve(type: record.contractType, to: recipient, tokenId: tokenId)
        }
    }

    func transfer(to address: String) {
        perform { [service, record] in
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
        perform { [service, record] in try await service.burn(type: record.contractType, tokenId: try self.validTokenId()) }
    }

    private func validTokenId() throws -> BigUInt {
        guard let value = BigUInt(tokenId), value >= 0 else { throw SRC721ValidationError.invalidTokenId }
        return value
    }

    @MainActor
    private func validateUpdate(
        baseURI: String,
        maxSupply: String,
        mintPrice: String,
        allowListAddresses: String,
        allowListAmounts: String,
        orgName: String,
        description: String,
        officialURL: String,
        whitePaperURL: String,
        logo: Data?
    ) -> Bool {
        clearUpdateCautions()
        var isValid = true

        do { _ = try SRC721Validation.optionalBaseURI(baseURI) }
        catch { baseURICautionState = caution(for: error); isValid = false }
        do { _ = try SRC721Validation.amount(maxSupply, field: "safe_zone.src721.field.max_supply".localized) }
        catch { maxSupplyCautionState = caution(for: error); isValid = false }
        if let maximum = BigUInt(maxSupply), let current = contractState, maximum < current.totalSupply {
            maxSupplyCautionState = caution(for: SRC721ValidationError.invalidAmount("safe_zone.src721.field.max_supply".localized))
            isValid = false
        }
        do { _ = try SRC721Validation.amount(mintPrice, field: "safe_zone.src721.field.mint_price".localized, allowZero: true) }
        catch { mintPriceCautionState = caution(for: error); isValid = false }

        let hasAddresses = !allowListAddresses.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAmounts = !allowListAmounts.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasAddresses || hasAmounts {
            do { _ = try SRC721Validation.allowList(addresses: allowListAddresses, amounts: allowListAmounts) }
            catch { allowListCautionState = caution(for: error); isValid = false }
        }

        if let logo {
            do { _ = try SRC721Validation.logo(logo) }
            catch { logoCautionState = caution(for: error); isValid = false }
        }
        return isValid
    }

    private func clearUpdateCautions() {
        baseURICautionState = .none
        maxSupplyCautionState = .none
        mintPriceCautionState = .none
        allowListCautionState = .none
        orgNameCautionState = .none
        descriptionCautionState = .none
        officialURLCautionState = .none
        whitePaperURLCautionState = .none
        logoCautionState = .none
    }

    private func caution(for error: Error) -> CautionState {
        .caution(Caution(text: error.localizedDescription, type: .error))
    }

    private func perform(_ operation: @escaping () async throws -> String) {
        perform { [operation] in [try await operation()] }
    }

    private func perform(_ operation: @escaping () async throws -> [String]) {
        guard operationState != .sending else { return }
        operationState = .sending
        operationMessage = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                let hashes = try await operation()
                guard !hashes.isEmpty else { throw Web3Error.processingError(desc: "No transaction generated") }
                let allSucceeded = await trackTransactions(hashes)
                await MainActor.run {
                    self.operationState = allSucceeded ? .completed : .failed
                    self.operationMessage = hashes.joined(separator: "\n")
                    self.refresh()
                }
            } catch let batchError as SRC721BatchOperationError {
                _ = await trackTransactions(batchError.submittedHashes)
                await MainActor.run {
                    self.operationState = .failed
                    self.operationMessage = batchError.localizedDescription
                }
            } catch {
                await MainActor.run {
                    self.operationState = .failed
                    self.operationMessage = error.localizedDescription
                }
            }
        }
    }

    private func trackTransactions(_ hashes: [String]) async -> Bool {
        var allSucceeded = true
        for hash in hashes {
            let transactionID = UUID()
            let createdAt = Date()
            let tokenId = self.tokenId.isEmpty ? nil : self.tokenId
            self.storage.save(transaction: SRC721TransactionRecord(
                id: transactionID, accountId: self.record.accountId, chainId: self.record.chainId,
                walletAddress: self.record.walletAddress, contractAddress: self.record.contractAddress,
                operation: "SRC721", tokenId: tokenId, transactionHash: hash, status: .pending,
                errorMessage: nil, createdAt: createdAt
            ))

            do {
                let success = try await self.service.waitForTransaction(hash)
                self.storage.save(transaction: SRC721TransactionRecord(
                    id: transactionID, accountId: self.record.accountId, chainId: self.record.chainId,
                    walletAddress: self.record.walletAddress, contractAddress: self.record.contractAddress,
                    operation: "SRC721", tokenId: tokenId, transactionHash: hash,
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
            operationMessage = SRC721ValidationError.emptyField("safe_zone.src721.field.value".localized).localizedDescription
            return
        }
        perform { [service, record] in
            let hashes = try await service.updateMetadata(type: record.contractType, orgName: orgName, description: description, officialURL: officialURL, whitePaperURL: whitePaperURL, logo: logo)
            return hashes
        }
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
