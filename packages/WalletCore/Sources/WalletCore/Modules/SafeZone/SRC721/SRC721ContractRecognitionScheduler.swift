import BigInt
import Foundation
import Web3Core
import web3swift

actor SRC721ContractRecognitionScheduler {
    enum Candidate: Hashable, Sendable {
        case contract(chainId: Int, address: String)
    }

    typealias Checker = @Sendable (Candidate) async throws -> Bool

    static let shared = SRC721ContractRecognitionScheduler(
        storage: .shared,
        checker: { candidate in try await SRC721ContractRecognitionScheduler.check(candidate) }
    )

    private static let erc721InterfaceId = "0x80ac58cd"
    private static let erc165ABI = """
    [{"inputs":[{"internalType":"bytes4","name":"interfaceId","type":"bytes4"}],"name":"supportsInterface","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"}]
    """

    private let storage: SRC721Storage
    private let checker: Checker
    private let maxConcurrentChecks: Int
    private let maxPendingChecks: Int
    private var pending = [Candidate]()
    private var queued = Set<Candidate>()
    private var active = Set<Candidate>()
    private var retryAfter = [Candidate: Date]()

    init(storage: SRC721Storage, maxConcurrentChecks: Int = 2, maxPendingChecks: Int = 128, checker: @escaping Checker) {
        self.storage = storage
        self.maxConcurrentChecks = max(1, maxConcurrentChecks)
        self.maxPendingChecks = max(1, maxPendingChecks)
        self.checker = checker
    }

    func schedule(_ candidate: Candidate) {
        guard cachedResult(for: candidate) == nil,
              !queued.contains(candidate),
              !active.contains(candidate),
              pending.count < maxPendingChecks,
              retryAfter[candidate].map({ $0 <= Date() }) ?? true else {
            return
        }

        pending.append(candidate)
        queued.insert(candidate)
        startPendingChecks()
    }

    private func startPendingChecks() {
        while active.count < maxConcurrentChecks, !pending.isEmpty {
            let candidate = pending.removeFirst()
            queued.remove(candidate)
            active.insert(candidate)

            let checker = self.checker
            Task(priority: .utility) {
                let result = try? await checker(candidate)
                self.complete(candidate, result: result)
            }
        }
    }

    private func complete(_ candidate: Candidate, result: Bool?) {
        active.remove(candidate)

        if let result {
            retryAfter.removeValue(forKey: candidate)
            save(result, for: candidate)
            if result {
                NotificationCenter.default.post(name: .src721ContractRecognitionUpdated, object: nil)
            }
        } else {
            // An RPC failure is temporary: avoid a tight retry loop while keeping the
            // transaction list independent from network availability.
            if retryAfter.count >= maxPendingChecks * 2 {
                let now = Date()
                retryAfter = retryAfter.filter { $0.value > now }
            }
            retryAfter[candidate] = Date().addingTimeInterval(45)
        }

        startPendingChecks()
    }

    private func cachedResult(for candidate: Candidate) -> Bool? {
        switch candidate {
        case let .contract(chainId, address):
            storage.recognizedSRC721Contract(chainId: chainId, contractAddress: address)
        }
    }

    private func save(_ result: Bool, for candidate: Candidate) {
        switch candidate {
        case let .contract(chainId, address):
            storage.saveSRC721ContractRecognition(chainId: chainId, contractAddress: address, isSRC721: result)
        }
    }

    private static func check(_ candidate: Candidate) async throws -> Bool {
        guard case let .contract(chainId, address) = candidate else { return false }
        let context = try Safe4Network.supportedContext(chainId: chainId)
        let web3 = try await Web3.new(context.rpcUrl, network: Networks.Custom(networkID: BigUInt(context.chainId)))
        guard let contractAddress = EthereumAddress(address) else { return false }
        return try await supportsERC721(web3: web3, address: contractAddress)
    }

    private static func supportsERC721(web3: Web3, address: EthereumAddress) async throws -> Bool {
        guard let contract = web3.contract(erc165ABI, at: address),
              let operation = contract.createReadOperation("supportsInterface", parameters: [erc721InterfaceId]) else {
            return false
        }

        let response = try await operation.callContractMethod()
        guard let isERC721 = response["0"] as? Bool else {
            throw RecognitionError.invalidResponse
        }
        return isERC721
    }

    private enum RecognitionError: Error {
        case invalidResponse
    }
}

extension Notification.Name {
    static let src721ContractRecognitionUpdated = Notification.Name("safe_zone.src721.contract_recognition_updated")
}
