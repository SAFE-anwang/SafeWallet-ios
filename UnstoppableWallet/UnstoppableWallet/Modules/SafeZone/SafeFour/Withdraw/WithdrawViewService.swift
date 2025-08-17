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
        return try await Web3.new( url, network: Networks.Custom(networkID: BigUInt(chain.id)))
    }
}

extension WithdrawViewService {
    
    func withdrawByID(ids:[BigUInt]) async throws -> String {
        try await web3().safe4.accountmanager.withdrawByID(privateKey: privateKey, ids: ids)
    }
}

// node
extension WithdrawViewService {
    
    func totalNum() async throws -> BigUInt {
        try await web3().safe4.accountmanager.getAvailableAmount(userAddress).num
    }
    
    func getAvailableIDs(start: BigUInt, count: BigUInt) async throws -> [BigUInt] {
        try await web3().safe4.accountmanager.getAvailableIDs(userAddress, start, count)
    }
    
    func isMasterNodeFounder(_ addr: Web3Core.EthereumAddress) async throws -> Bool {
        try await web3().safe4.masternode.existFounder(addr)
    }
    
    func isSuperNodeFounder(_ addr: Web3Core.EthereumAddress) async throws -> Bool {
        try await web3().safe4.supernode.existFounder(addr)
    }
}

// proposal
extension WithdrawViewService {
    func mineProposalNum() async throws -> BigUInt {
        return try await web3().safe4.proposal.getMineNum(userAddress)
    }
    
    func mineProposalIds(start: BigUInt, count: BigUInt) async throws -> [BigUInt] {
        return try await web3().safe4.proposal.getMines(userAddress, start, count)
    }
    
    func getProposalRewardIDs(id: BigUInt) async throws -> [BigUInt] {
        try await web3().safe4.proposal.getRewardIDs(id)
    }
    
    func getInfo(id: BigUInt) async throws -> ProposalInfo {
        try await web3().safe4.proposal.getInfo(id)
    }
}

// locked
extension WithdrawViewService {
    
    func getVotedIDNum4Voter() async throws -> BigUInt {
        let address = Web3Core.EthereumAddress(evmKit.receiveAddress.hex)!
        return try await web3().safe4.snvote.getVotedIDNum4Voter(address)
    }
    
    func getVotedIDs4Voter(start: BigUInt, count: BigUInt) async throws -> [BigUInt] {
        let address = Web3Core.EthereumAddress(evmKit.receiveAddress.hex)!
        return try await web3().safe4.snvote.getVotedIDs4Voter(address, start, count)
    }
}

// info
extension WithdrawViewService {
    
    func getRecordByID(id: BigUInt) async throws -> web3swift.AccountRecord {
        try await web3().safe4.accountmanager.getRecordByID(id)
    }
    
    func getRecordUseInfo(id: BigUInt) async throws -> RecordUseInfo {
        try await web3().safe4.accountmanager.getRecordUseInfo(id)
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
