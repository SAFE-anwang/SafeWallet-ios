import Foundation

final class SRC721Storage {
    static let shared = SRC721Storage()

    private let defaults: UserDefaults
    private let contractsKey = "safe_zone.src721.contracts"
    private let transactionsKey = "safe_zone.src721.transactions"

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

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
