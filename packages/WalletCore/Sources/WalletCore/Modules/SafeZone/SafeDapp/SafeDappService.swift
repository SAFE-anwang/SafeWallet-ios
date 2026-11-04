import BigInt
import EvmKit
import Foundation
import Web3Core
import web3swift

class SafeDappService {
    private let privateKey: Data
    private let userAddress: SafeDappEthereumAddress
    private let chainId: Int

    init(privateKey: Data, userAddress: String, chainId: Int = Safe4Network.currentChainId) {
        self.privateKey = privateKey
        self.userAddress = SafeDappEthereumAddress(userAddress)!
        self.chainId = chainId
    }

    private static func web3(chainId: Int) async throws -> Web3 {
        let context = try Safe4Network.supportedContext(chainId: chainId)
        return try await Web3.new(
            context.rpcUrl,
            network: Networks.Custom(networkID: BigUInt(context.chainId))
        )
    }

    private static func dapp(chainId: Int) async throws -> DAppManager {
        let web3 = try await web3(chainId: chainId)
        return web3.safe4.dapp
    }

    private func dapp() async throws -> DAppManager {
        try await Self.dapp(chainId: chainId)
    }
}

extension SafeDappService {
    var account: SafeDappEthereumAddress { userAddress }

    func availableBalance() async throws -> BigUInt {
        let web3 = try await Self.web3(chainId: chainId)
        return try await web3.eth.getBalance(for: userAddress)
    }

    func register(data: SafeDappFormData) async throws -> String {
        let name = data.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = SafeDappValidation.validateRequired(name, min: 5, max: 50, title: SafeDappField.name.title) {
            throw SafeDappValidationError(message: error)
        }
        let contractAddr = try SafeDappValidation.ethereumAddress(data.contractAddr, title: SafeDappField.contractAddr.title).get()
        let runUrl = try SafeDappValidation.normalizedUrl(data.runUrl, required: true, title: SafeDappField.runUrl.title, min: 15, max: 200).get()
        let description = data.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = SafeDappValidation.validateRequired(description, min: 10, max: 1024, title: SafeDappField.description.title) {
            throw SafeDappValidationError(message: error)
        }
        let keyword = try SafeDappValidation.normalizedKeyword(data.keyword, title: SafeDappField.keyword.title).get()
        let gitUrl = try SafeDappValidation.normalizedUrl(data.gitUrl, required: false, title: SafeDappField.gitUrl.title, min: 0, max: 200).get()
        let officialUrl = try SafeDappValidation.normalizedUrl(data.officialUrl, required: false, title: SafeDappField.officialUrl.title, min: 0, max: 200).get()
        let officialEmail = try SafeDappValidation.optionalEmail(data.officialEmail, title: SafeDappField.officialEmail.title).get()

        let web3 = try await Self.web3(chainId: chainId)
        let manager = web3.safe4.dapp
        let transactionHash = try await manager.register(
            privateKey: privateKey,
            name: name,
            contractAddr: contractAddr,
            runUrl: runUrl,
            description: description,
            gitUrl: gitUrl,
            officialUrl: officialUrl,
            officialEmail: officialEmail
        )

        guard let hashData = Data.fromHex(transactionHash), !hashData.isEmpty else {
            throw SafeDappPostRegistrationError(isTransactionConfirmed: false)
        }
        let receipt: TransactionReceipt
        do {
            receipt = try await TransactionPollingTask(transactionHash: hashData, web3Instance: web3).wait()
        } catch {
            throw SafeDappPostRegistrationError(isTransactionConfirmed: false)
        }
        guard receipt.status == .ok else {
            throw SafeDappValidationError(message: "safe_dapp.error.register_failed".localized)
        }

        guard !keyword.isEmpty else { return transactionHash }

        let info: DAppInfo
        do {
            info = try await Self.retrying {
                let info = try await manager.getInfoByName(name)
                try SafeDappValidation.validateID(info.id)
                return info
            }
        } catch {
            throw SafeDappPostRegistrationError(isTransactionConfirmed: true)
        }

        do {
            let keywordTransactionHash = try await manager.setKeyword(privateKey: privateKey, id: info.id, keyword: keyword)
            guard let keywordHashData = Data.fromHex(keywordTransactionHash), !keywordHashData.isEmpty else {
                throw SafeDappPostRegistrationError(isTransactionConfirmed: true)
            }
            let keywordReceipt = try await TransactionPollingTask(transactionHash: keywordHashData, web3Instance: web3).wait()
            guard keywordReceipt.status == .ok else {
                throw SafeDappPostRegistrationError(isTransactionConfirmed: true)
            }
        } catch {
            throw SafeDappPostRegistrationError(isTransactionConfirmed: true)
        }
        return transactionHash
    }

    static func retrying<T>(
        attempts: Int = 6,
        delayNanoseconds: UInt64 = 1_000_000_000,
        operation: () async throws -> T
    ) async throws -> T {
        guard attempts > 0 else {
            throw SafeDappValidationError(message: "safe_dapp.error.register_failed".localized)
        }

        var lastError: Error?
        for attempt in 0 ..< attempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                if attempt + 1 < attempts {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                }
            }
        }

        throw lastError ?? SafeDappValidationError(message: "safe_dapp.error.register_failed".localized)
    }

    func getMineNum() async throws -> BigUInt {
        try await dapp().getMineNum(userAddress)
    }

    func getMineIDs(start: BigUInt, count: BigUInt) async throws -> [BigUInt] {
        try SafeDappValidation.validatePage(start: start, count: count, total: try await getMineNum())
        return try await dapp().getMineIDs(userAddress, start, count)
    }

    func getInfo(id: BigUInt) async throws -> DAppInfo {
        try SafeDappValidation.validateID(id)
        return try await dapp().getInfo(id)
    }

    func getLogo(id: BigUInt) async throws -> Data {
        try SafeDappValidation.validateID(id)
        return try await dapp().getLogo(id)
    }

    func isFrozen(id: BigUInt) async throws -> Bool {
        try SafeDappValidation.validateID(id)
        return try await dapp().isFrozen(id)
    }

    func remove(id: BigUInt) async throws -> String {
        try SafeDappValidation.validateID(id)
        return try await dapp().remove(privateKey: privateKey, id: id)
    }

    func getLogoPayAmount() async throws -> BigUInt {
        try await dapp().getLogoPayAmount()
    }

    func setLogo(id: BigUInt, logo: Data) async throws -> String {
        try SafeDappValidation.validateID(id)
        try SafeDappValidation.validateLogo(logo)
        return try await dapp().setLogo(privateKey: privateKey, id: id, logo: logo)
    }

    func update(field: SafeDappField, id: BigUInt, value: String) async throws -> String {
        try SafeDappValidation.validateID(id)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch field {
        case .name:
            if let error = SafeDappValidation.validateRequired(trimmed, min: 5, max: 50, title: field.title) {
                throw SafeDappValidationError(message: error)
            }
            return try await dapp().setName(privateKey: privateKey, id: id, name: trimmed)
        case .contractAddr:
            let address = try SafeDappValidation.ethereumAddress(trimmed, title: field.title).get()
            return try await dapp().setContractAddr(privateKey: privateKey, id: id, contractAddr: address)
        case .runUrl:
            let url = try SafeDappValidation.normalizedUrl(trimmed, required: true, title: field.title, min: 15, max: 200).get()
            return try await dapp().setRunUrl(privateKey: privateKey, id: id, runUrl: url)
        case .gitUrl:
            let url = try SafeDappValidation.normalizedUrl(trimmed, required: false, title: field.title, min: 0, max: 200).get()
            return try await dapp().setGitUrl(privateKey: privateKey, id: id, gitUrl: url)
        case .officialUrl:
            let url = try SafeDappValidation.normalizedUrl(trimmed, required: false, title: field.title, min: 0, max: 200).get()
            return try await dapp().setOfficialUrl(privateKey: privateKey, id: id, officialUrl: url)
        case .officialEmail:
            let email = try SafeDappValidation.optionalEmail(trimmed, title: field.title).get()
            return try await dapp().setOfficialEmail(privateKey: privateKey, id: id, officialEmail: email)
        case .officialAccount:
            let address = try SafeDappValidation.ethereumAddress(trimmed, title: field.title).get()
            return try await dapp().setOfficialAccount(privateKey: privateKey, id: id, account: address)
        case .description:
            if let error = SafeDappValidation.validateRequired(trimmed, min: 10, max: 1024, title: field.title) {
                throw SafeDappValidationError(message: error)
            }
            return try await dapp().setDescription(privateKey: privateKey, id: id, description: trimmed)
        case .keyword:
            if let error = SafeDappValidation.validateOptional(trimmed, min: 0, max: 200, title: field.title) {
                throw SafeDappValidationError(message: error)
            }
            return try await dapp().setKeyword(privateKey: privateKey, id: id, keyword: trimmed)
        }
    }

    func exists(field: SafeDappField, value: String) async throws -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch field {
        case .name:
            return try await dapp().existName(trimmed)
        case .contractAddr:
            let address = try SafeDappValidation.ethereumAddress(trimmed, title: field.title).get()
            return try await dapp().existContractAddr(address)
        case .runUrl:
            let url = try SafeDappValidation.normalizedUrl(trimmed, required: true, title: field.title, min: 15, max: 200).get()
            return try await dapp().existRunUrl(url)
        default:
            return false
        }
    }

    static func publishedDapps(chainId: Int = Safe4Network.currentChainId) async throws -> [DAppInfo] {
        let items = try await publishedDappItems(chainId: chainId)
        return items.map(\.info)
    }

    static func isFrozen(id: BigUInt, chainId: Int = Safe4Network.currentChainId) async throws -> Bool {
        try SafeDappValidation.validateID(id)
        return try await dapp(chainId: chainId).isFrozen(id)
    }

    static func publishedDappItems(
        chainId: Int = Safe4Network.currentChainId,
        onItemsUpdated: (([SafeDappPublishedItem]) async -> Void)? = nil
    ) async throws -> [SafeDappPublishedItem] {
        try await SafeDappPublishedDappsRequest.shared.load(chainId: chainId, onItemsUpdated: onItemsUpdated)
    }

    fileprivate static func fetchPublishedDappItems(
        chainId: Int,
        onItemsUpdated: @escaping ([SafeDappPublishedItem]) async -> Void
    ) async throws -> [SafeDappPublishedItem] {
        let web3 = try await web3(chainId: chainId)
        let dapp = web3.safe4.dapp
        let total = try await dapp.getNum()
        var ids: [BigUInt] = []
        var start = BigUInt.zero
        let pageSize = BigUInt(100)

        while start < total {
            let count = min(pageSize, total - start)
            try SafeDappValidation.validatePage(start: start, count: count, total: total)
            let pageIDs = try await dapp.getIDs(start, count)
            guard !pageIDs.isEmpty else { break }
            ids.append(contentsOf: pageIDs)
            start += BigUInt(pageIDs.count)
        }

        // Query independent reads concurrently, but cap total fan-out to avoid
        // flooding the RPC endpoint. Start each logo as soon as its info arrives,
        // rather than waiting for every info request to finish first.
        let concurrencyLimit = 4
        return await fetchInfoAndLogoItems(
            ids: ids,
            web3: web3,
            concurrencyLimit: concurrencyLimit,
            onItemsUpdated: onItemsUpdated
        )
    }

    private static func fetchInfoAndLogoItems(
        ids: [BigUInt],
        web3: Web3,
        concurrencyLimit: Int,
        onItemsUpdated: @escaping ([SafeDappPublishedItem]) async -> Void
    ) async -> [SafeDappPublishedItem] {
        guard !ids.isEmpty else {
            await onItemsUpdated([])
            return []
        }

        return await withTaskGroup(of: SafeDappReadResult.self) { group in
            var nextIndex = 0
            var results = Array<SafeDappPublishedItem?>(repeating: nil, count: ids.count)
            var queuedJobs: [SafeDappReadJob] = []
            var nextQueuedJob = 0
            var activeTaskCount = 0
            let safeLimit = max(1, concurrencyLimit)

            func addTask(for job: SafeDappReadJob) {
                switch job {
                case .info(let index):
                    group.addTask {
                        // A broken item must not prevent the remaining entries from displaying.
                        let info = try? await Web3.Safe4(web3: web3).dapp.getInfo(ids[index])
                        return .info(index: index, info: info)
                    }
                case .logo(let index, let info):
                    group.addTask {
                        let data = try? await Web3.Safe4(web3: web3).dapp.getLogo(info.id)
                        return .logo(index: index, data: data.flatMap { $0.isEmpty ? nil : $0 })
                    }
                }
                activeTaskCount += 1
            }

            while nextIndex < min(safeLimit, ids.count) {
                addTask(for: .info(index: nextIndex))
                nextIndex += 1
            }

            while activeTaskCount > 0, let result = await group.next() {
                activeTaskCount -= 1
                switch result {
                case .info(let index, let info):
                    if let info {
                        results[index] = SafeDappPublishedItem(info: info, logoData: nil)
                        queuedJobs.append(.logo(index: index, info: info))
                    }
                    // Publish detail rows immediately, then publish each logo as
                    // soon as its independent RPC completes.
                    await onItemsUpdated(results.compactMap { $0 })
                    if nextIndex < ids.count {
                        queuedJobs.append(.info(index: nextIndex))
                        nextIndex += 1
                    }
                case .logo(let index, let data):
                    if let item = results[index] {
                        results[index] = SafeDappPublishedItem(info: item.info, logoData: data)
                        await onItemsUpdated(results.compactMap { $0 })
                    }
                }

                while activeTaskCount < safeLimit, nextQueuedJob < queuedJobs.count {
                    addTask(for: queuedJobs[nextQueuedJob])
                    nextQueuedJob += 1
                }
            }

            return results.compactMap { $0 }
        }
    }
}

private enum SafeDappReadJob {
    case info(index: Int)
    case logo(index: Int, info: DAppInfo)
}

private enum SafeDappReadResult {
    case info(index: Int, info: DAppInfo?)
    case logo(index: Int, data: Data?)
}

/// Coalesces overlapping loads from the ALL and SAFE market tabs. It deliberately
/// retains no completed result, so a later refresh still reads current chain data.
private actor SafeDappPublishedDappsRequest {
    static let shared = SafeDappPublishedDappsRequest()

    private var inFlight: [Int: Task<[SafeDappPublishedItem], Error>] = [:]
    private var progressHandlers: [Int: [UUID: ([SafeDappPublishedItem]) async -> Void]] = [:]
    private var latestItems: [Int: [SafeDappPublishedItem]] = [:]

    func load(
        chainId: Int,
        onItemsUpdated: (([SafeDappPublishedItem]) async -> Void)?
    ) async throws -> [SafeDappPublishedItem] {
        let handlerId = UUID()
        if let onItemsUpdated {
            progressHandlers[chainId, default: [:]][handlerId] = onItemsUpdated
            if let latestItems = latestItems[chainId] {
                await onItemsUpdated(latestItems)
            }
        }

        let task: Task<[SafeDappPublishedItem], Error>
        if let existingTask = inFlight[chainId] {
            task = existingTask
        } else {
            task = Task {
                try await SafeDappService.fetchPublishedDappItems(chainId: chainId) { items in
                    await self.publishItems(items, chainId: chainId)
                }
            }
            inFlight[chainId] = task
        }

        do {
            let items = try await task.value
            progressHandlers[chainId]?[handlerId] = nil
            if inFlight[chainId] != nil {
                inFlight[chainId] = nil
                latestItems[chainId] = nil
                progressHandlers[chainId] = nil
            }
            return items
        } catch {
            progressHandlers[chainId]?[handlerId] = nil
            if inFlight[chainId] != nil {
                inFlight[chainId] = nil
                latestItems[chainId] = nil
                progressHandlers[chainId] = nil
            }
            throw error
        }
    }

    private func publishItems(_ items: [SafeDappPublishedItem], chainId: Int) async {
        latestItems[chainId] = items
        let handlers = progressHandlers[chainId].map { Array($0.values) } ?? []
        for handler in handlers {
            await handler(items)
        }
    }
}
