import web3swift
import Web3Core
import EvmKit
import BigInt
import Foundation

class ProposalService {
    let networkSession = Safe4NetworkSession()
    let type: ProposalModule.ProposalType
    let chainId: Int
    let proposalStorageManager: ProposalStorageManager
    let reminderScope: Safe4CacheScope

    init(type: ProposalModule.ProposalType, chainId: Int = Safe4Network.currentChainId) {
        self.type = type
        self.chainId = chainId
        let owner: String
        switch type {
        case .All: owner = "public"
        case let .Mine(address): owner = address
        }
        proposalStorageManager = ProposalStorageManager(scope: Safe4CacheScope(chainId: chainId, owner: owner))
        reminderScope = Safe4CacheScope(chainId: chainId, owner: Core.shared.accountManager.activeAccount?.id ?? "")
    }

    private func web3() async throws -> Web3 {
        let context = try Safe4Network.activeContext(chainId: chainId)
        try networkSession.check()
        try Task.checkCancellation()
        let web3 = try await Web3.new(context.rpcUrl, network: Networks.Custom(networkID: BigUInt(context.chainId)))
        try networkSession.check()
        try Task.checkCancellation()
        _ = try Safe4Network.activeContext(chainId: context.chainId)
        return web3
    }

    private func withRetry<T>(
        maxAttempts: Int = 2,
        retryDelayNanoseconds: UInt64 = 200_000_000,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                guard attempt < maxAttempts else { break }
                try? await Task.sleep(nanoseconds: retryDelayNanoseconds)
            }
        }
        throw lastError ?? NSError(domain: "ProposalService", code: -1)
    }
}

extension ProposalService {
    func getTotalNum() async throws -> Int {
        switch type {
        case .All:
            let num = try await getNum()
            return Int(num)

        case let .Mine(address):
            let num = try await mineProposalNum(address: address)
            return Int(num)
        }
    }

    func hasNewProposals() async throws -> Bool {
        let currentTotal = try await getTotalNum()
        guard let cachedTotal = proposalStorageManager.getPageControl()?.totalNum else {
            return true
        }
        return cachedTotal < currentTotal
    }

    func proposalIds(offset: Int, count: Int) async throws -> [BigUInt] {
        switch type {
        case .All:
            return try await allProposalIds(offset: offset, count: count)
        case let .Mine(address):
            return try await mineProposalIds(address: address, offset: offset, count: count)
        }
    }

    func getInfo(id: BigUInt) async throws -> ProposalInfo {
        try await withRetry { try await self.web3().safe4.proposal.getInfo(id) }
    }

    func exist(_ id: BigUInt) async throws -> Bool {
        try await withRetry { try await self.web3().safe4.proposal.exist(id) }
    }

}

// all Proposal
extension ProposalService {
    func getNum() async throws -> BigUInt {
        try await withRetry { try await self.web3().safe4.proposal.getNum() }
    }

    func allProposalIds(offset: Int, count: Int) async throws -> [BigUInt] {
        try await withRetry { try await self.web3().safe4.proposal.getAll(BigUInt(offset), BigUInt(count)) }
    }
}

// mine Proposal
private extension ProposalService {

    func mineProposalNum(address: String) async throws -> BigUInt {
        let creator = Web3Core.EthereumAddress(address)!
        return try await withRetry { try await self.web3().safe4.proposal.getMineNum(creator) }
    }

    func mineProposalIds(address: String, offset: Int, count: Int) async throws -> [BigUInt] {
        let creator = Web3Core.EthereumAddress(address)!
        return try await withRetry { try await self.web3().safe4.proposal.getMines(creator, BigUInt(offset), BigUInt(count)) }
    }

}
