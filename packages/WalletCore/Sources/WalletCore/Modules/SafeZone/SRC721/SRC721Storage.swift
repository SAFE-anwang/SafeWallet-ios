import Foundation

final class SRC721Storage {
    static let shared = SRC721Storage()

    private let defaults: UserDefaults
    private let cacheLock = NSLock()
    private let contractsKey = "safe_zone.src721.contracts"
    private let transactionsKey = "safe_zone.src721.transactions"
    private let allowListEntriesKey = "safe_zone.src721.allow_list_entries"
    private let hiddenContractsKey = "safe_zone.src721.hidden_contracts"
    private let recognizedContractsKey = "safe_zone.src721.recognized_contracts"
    private let maxRecognitionCacheEntries = 512
    private var cachedContractLookupIndex: ContractLookupIndex?
    private var cachedRecognizedContracts: [String: Bool]?

    private struct ContractLookupIndex {
        let contractKeys: Set<String>
        let walletContractKeys: Set<String>
        let deploymentKeys: Set<String>
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func contracts(accountId: String, chainId: Int, walletAddress: String) -> [SRC721ContractRecord] {
        (load([SRC721ContractRecord].self, key: contractsKey) ?? [])
            .filter {
                $0.accountId == accountId &&
                $0.chainId == chainId &&
                $0.walletAddress.lowercased() == walletAddress.lowercased()
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func containsContract(chainId: Int, walletAddress: String, contractAddress: String) -> Bool {
        contractLookupIndex().walletContractKeys.contains(
            walletContractKey(chainId: chainId, walletAddress: walletAddress, contractAddress: contractAddress)
        )
    }

    func containsContract(chainId: Int, contractAddress: String) -> Bool {
        contractLookupIndex().contractKeys.contains(contractKey(chainId: chainId, address: contractAddress))
    }

    func recognizedSRC721Contract(chainId: Int, contractAddress: String) -> Bool? {
        recognizedContractResults()[contractRecognitionKey(chainId: chainId, address: contractAddress)]
    }

    func saveSRC721ContractRecognition(chainId: Int, contractAddress: String, isSRC721: Bool) {
        var recognized = recognizedContractResults()
        recognized[contractRecognitionKey(chainId: chainId, address: contractAddress)] = isSRC721
        recognized = trimmedRecognitionCache(recognized)
        save(recognized, key: recognizedContractsKey)
        cacheLock.lock()
        cachedRecognizedContracts = recognized
        cacheLock.unlock()
    }

    private func contractRecognitionKey(chainId: Int, address: String) -> String {
        "\(chainId):\(address.lowercased())"
    }

    func containsDeployment(chainId: Int, walletAddress: String, transactionHash: String) -> Bool {
        contractLookupIndex().deploymentKeys.contains(
            deploymentKey(chainId: chainId, walletAddress: walletAddress, transactionHash: transactionHash)
        )
    }

    private func normalizedTransactionHash(_ hash: String) -> String {
        let normalized = hash.lowercased()
        return normalized.hasPrefix("0x") ? String(normalized.dropFirst(2)) : normalized
    }

    func save(contract: SRC721ContractRecord) {
        var records = load([SRC721ContractRecord].self, key: contractsKey) ?? []
        records.removeAll {
            guard $0.accountId == contract.accountId,
                  $0.chainId == contract.chainId,
                  $0.walletAddress.lowercased() == contract.walletAddress.lowercased() else {
                return false
            }
            if $0.contractAddress.lowercased() == contract.contractAddress.lowercased() {
                return true
            }
            return $0.deployTransactionHash != nil && $0.deployTransactionHash == contract.deployTransactionHash
        }
        records.append(contract)
        save(records, key: contractsKey)
        cacheLock.lock()
        cachedContractLookupIndex = nil
        cacheLock.unlock()
    }

    func update(contract: SRC721ContractRecord) {
        save(contract: contract)
    }

    func remove(contract: SRC721ContractRecord) {
        var records = load([SRC721ContractRecord].self, key: contractsKey) ?? []
        records.removeAll {
            $0.accountId == contract.accountId &&
            $0.chainId == contract.chainId &&
            $0.walletAddress.lowercased() == contract.walletAddress.lowercased() &&
            $0.contractAddress.lowercased() == contract.contractAddress.lowercased()
        }
        save(records, key: contractsKey)
        cacheLock.lock()
        cachedContractLookupIndex = nil
        cacheLock.unlock()
    }

    func hide(contract: SRC721ContractRecord) {
        var addresses = load([String].self, key: hiddenContractsKey) ?? []
        let key = hiddenContractKey(contract)
        guard !addresses.contains(key) else { return }
        addresses.append(key)
        save(addresses, key: hiddenContractsKey)
        remove(contract: contract)
    }

    func unhide(contract: SRC721ContractRecord) {
        let key = hiddenContractKey(contract)
        var addresses = load([String].self, key: hiddenContractsKey) ?? []
        addresses.removeAll { $0 == key }
        save(addresses, key: hiddenContractsKey)
    }

    func isHidden(contract: SRC721ContractRecord) -> Bool {
        (load([String].self, key: hiddenContractsKey) ?? []).contains(hiddenContractKey(contract))
    }

    private func hiddenContractKey(_ contract: SRC721ContractRecord) -> String {
        "\(contract.accountId):\(contract.chainId):\(contract.walletAddress.lowercased()):\(contract.contractAddress.lowercased())"
    }

    private func contractLookupIndex() -> ContractLookupIndex {
        cacheLock.lock()
        let cached = cachedContractLookupIndex
        cacheLock.unlock()
        if let cached { return cached }

        let records = load([SRC721ContractRecord].self, key: contractsKey) ?? []
        let loaded = ContractLookupIndex(
            contractKeys: Set(records.map { contractKey(chainId: $0.chainId, address: $0.contractAddress) }),
            walletContractKeys: Set(records.map {
                walletContractKey(chainId: $0.chainId, walletAddress: $0.walletAddress, contractAddress: $0.contractAddress)
            }),
            deploymentKeys: Set(records.compactMap { record in
                guard let transactionHash = record.deployTransactionHash else { return nil }
                return deploymentKey(chainId: record.chainId, walletAddress: record.walletAddress, transactionHash: transactionHash)
            })
        )

        cacheLock.lock()
        if cachedContractLookupIndex == nil {
            cachedContractLookupIndex = loaded
        }
        let result = cachedContractLookupIndex ?? loaded
        cacheLock.unlock()
        return result
    }

    private func recognizedContractResults() -> [String: Bool] {
        cacheLock.lock()
        let cached = cachedRecognizedContracts
        cacheLock.unlock()
        if let cached { return cached }

        let loaded = load([String: Bool].self, key: recognizedContractsKey) ?? [:]
        cacheLock.lock()
        if cachedRecognizedContracts == nil {
            cachedRecognizedContracts = loaded
        }
        let result = cachedRecognizedContracts ?? loaded
        cacheLock.unlock()
        return result
    }

    private func contractKey(chainId: Int, address: String) -> String {
        "\(chainId):\(address.lowercased())"
    }

    private func walletContractKey(chainId: Int, walletAddress: String, contractAddress: String) -> String {
        "\(chainId):\(walletAddress.lowercased()):\(contractAddress.lowercased())"
    }

    private func deploymentKey(chainId: Int, walletAddress: String, transactionHash: String) -> String {
        "\(chainId):\(walletAddress.lowercased()):\(normalizedTransactionHash(transactionHash))"
    }

    private func trimmedRecognitionCache(_ cache: [String: Bool]) -> [String: Bool] {
        guard cache.count > maxRecognitionCacheEntries else { return cache }
        var trimmed = cache
        for key in trimmed.keys.sorted().prefix(trimmed.count - maxRecognitionCacheEntries) {
            trimmed.removeValue(forKey: key)
        }
        return trimmed
    }

    func save(transaction: SRC721TransactionRecord) {
        var records = load([SRC721TransactionRecord].self, key: transactionsKey) ?? []
        records.removeAll { $0.id == transaction.id }
        records.append(transaction)
        save(records, key: transactionsKey)
    }

    func transactions(accountId: String, chainId: Int, walletAddress: String) -> [SRC721TransactionRecord] {
        (load([SRC721TransactionRecord].self, key: transactionsKey) ?? [])
            .filter {
                $0.accountId == accountId &&
                $0.chainId == chainId &&
                $0.walletAddress.lowercased() == walletAddress.lowercased()
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func allowListEntries(for contract: SRC721ContractRecord) -> [SRC721AllowListEntry] {
        (load([SRC721AllowListEntry].self, key: allowListEntriesKey) ?? [])
            .filter {
                $0.accountId == contract.accountId &&
                $0.chainId == contract.chainId &&
                $0.walletAddress.lowercased() == contract.walletAddress.lowercased() &&
                $0.contractAddress.lowercased() == contract.contractAddress.lowercased()
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(allowListEntry: SRC721AllowListEntry) {
        var entries = load([SRC721AllowListEntry].self, key: allowListEntriesKey) ?? []
        entries.removeAll { $0.id == allowListEntry.id }
        entries.append(allowListEntry)
        save(entries, key: allowListEntriesKey)
    }

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
