import Foundation
import web3swift
import Web3Core
import EvmKit
import BigInt
import RxSwift
import RxCocoa

class WithdrawViewService {
    let type: SafeWithdrawType
    private let privateKey: Data
    private let evmKit: EvmKit.Kit
    private static let retryAttempts = 2
    private static let retryDelayNanoseconds: UInt64 = 200_000_000

    init(type: SafeWithdrawType, privateKey: Data, evmKit: EvmKit.Kit) {
        self.type = type
        self.privateKey = privateKey
        self.evmKit = evmKit
    }
    
    var userAddress: Web3Core.EthereumAddress {
        Web3Core.EthereumAddress(evmKit.receiveAddress.hex)!
    }
    
    var lastBlockHeight: Int? {
        evmKit.lastBlockHeight
    }
    
    private func web3() async throws -> Web3 {
        let chain = Chain.safeFourChain()
        let url = RpcSource.safeFourRpcHttp().url
        return try await Web3.new(url, network: Networks.Custom(networkID: BigUInt(chain.id)))
    }

    private func withRetry<T>(
        maxAttempts: Int,
        retryDelayNanoseconds: UInt64,
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
        throw lastError ?? NSError(domain: "WithdrawViewService", code: -1)
    }

    private func withRetry<T>(
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withRetry(
            maxAttempts: WithdrawViewService.retryAttempts,
            retryDelayNanoseconds: WithdrawViewService.retryDelayNanoseconds,
            operation: operation
        )
    }
}

extension WithdrawViewService {
    
    func withdrawByID(type: web3swift.AccountManager.ContractType, ids:[BigUInt]) async throws -> String {
        try await withRetry {
            try await self.web3().safe4.accountmanager(type: type).withdrawByID(privateKey: self.privateKey, ids: ids)
        }
    }
    
    func removeVoteOrApproval(recordIDs: [BigUInt]) async throws -> String {
        try await withRetry {
            try await self.web3().safe4.snvote.removeVoteOrApproval(privateKey: self.privateKey, recordIDs: recordIDs)
        }
    }
}

// node
extension WithdrawViewService {
    
    func totalNum(type: web3swift.AccountManager.ContractType) async throws -> BigUInt {
        try await withRetry {
            try await self.web3().safe4.accountmanager(type: type).getAvailableAmount(self.userAddress).num
        }
    }
    
    func getAvailableIDs(type: web3swift.AccountManager.ContractType, start: BigUInt, count: BigUInt) async throws -> [BigUInt] {
        try await withRetry {
            try await self.web3().safe4.accountmanager(type: type).getAvailableIDs(self.userAddress, start, count)
        }
    }
    
    func isMasterNodeFounder(_ addr: Web3Core.EthereumAddress) async throws -> Bool {
        try await withRetry { try await self.web3().safe4.masternode.existFounder(addr) }
    }
    
    func isSuperNodeFounder(_ addr: Web3Core.EthereumAddress) async throws -> Bool {
        try await withRetry { try await self.web3().safe4.supernode.existFounder(addr) }
    }
}

// proposal
extension WithdrawViewService {
    func mineProposalNum() async throws -> BigUInt {
        return try await withRetry { try await self.web3().safe4.proposal.getMineNum(self.userAddress) }
    }
    
    func mineProposalIds(start: BigUInt, count: BigUInt) async throws -> [BigUInt] {
        return try await withRetry { try await self.web3().safe4.proposal.getMines(self.userAddress, start, count) }
    }
    
    func getProposalRewardIDs(id: BigUInt) async throws -> [BigUInt] {
        try await withRetry { try await self.web3().safe4.proposal.getRewardIDs(id) }
    }
    
    func getInfo(id: BigUInt) async throws -> ProposalInfo {
        try await withRetry { try await self.web3().safe4.proposal.getInfo(id) }
    }
}

// voted
extension WithdrawViewService {
    
    func getVotedIDNum4Voter() async throws -> BigUInt {
        let address = Web3Core.EthereumAddress(evmKit.receiveAddress.hex)!
        return try await withRetry { try await self.web3().safe4.snvote.getVotedIDNum4Voter(address) }
    }
    
    func getVotedIDs4Voter(start: BigUInt, count: BigUInt) async throws -> [BigUInt] {
        let address = Web3Core.EthereumAddress(evmKit.receiveAddress.hex)!
        return try await withRetry { try await self.web3().safe4.snvote.getVotedIDs4Voter(address, start, count) }
    }
    
//    func totalLockedNum(type: web3swift.AccountManager.ContractType) async throws -> BigUInt {
//        let address = Web3Core.EthereumAddress(evmKit.receiveAddress.hex)!
//        return try await web3().safe4.accountmanager(type: type).getLockedAmount(address).num
//    }
//    
//    func getLockedIDs(type: web3swift.AccountManager.ContractType, start: BigUInt, count: BigUInt) async throws -> [BigUInt] {
//        let address = Web3Core.EthereumAddress(evmKit.receiveAddress.hex)!
//        return try await web3().safe4.accountmanager(type: type).getLockedIDs(address, start, count)
//    }
}

// info
extension WithdrawViewService {
    
    func getRecordByID(id: BigUInt) async throws -> web3swift.AccountRecord {
        try await withRetry { try await self.web3().safe4.accountmanager.getRecordByID(id) }
    }
    
    func getRecordUseInfo(id: BigUInt) async throws -> RecordUseInfo {
        try await withRetry { try await self.web3().safe4.accountmanager.getRecordUseInfo(id) }
    }
}

extension WithdrawViewService {
    
    enum NodeType {
        case masterNode
        case superNode
    }
    
    enum NodeMemberType {
        case Creator
        case Partner
    }
}
