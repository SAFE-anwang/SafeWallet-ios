import Foundation
import web3swift
import Web3Core
import EvmKit
import BigInt
import RxSwift
import RxCocoa

class LockedRecoardService {
    private let privateKey: Data
    private let evmKit: EvmKit.Kit

    init(privateKey: Data, evmKit: EvmKit.Kit) {
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

extension LockedRecoardService {
    
    func withdrawByID(id: BigUInt) async throws -> String {
        try await web3().safe4.accountmanager.withdrawByID(privateKey: privateKey, ids: [id])
    }
}

// locked
extension LockedRecoardService {
    
    func totalLockedNum() async throws -> BigUInt {
        try await web3().safe4.accountmanager.getLockedAmount(userAddress).num
    }
    
    func getLockedIDs(start: BigUInt, count: BigUInt) async throws -> [BigUInt] {
        try await web3().safe4.accountmanager.getLockedIDs(userAddress, start, count)
    }
}

// proposal
extension LockedRecoardService {
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

// voted
extension LockedRecoardService {
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
extension LockedRecoardService {
    
    func getRecordByID(id: BigUInt) async throws -> web3swift.AccountRecord {
        try await web3().safe4.accountmanager.getRecordByID(id)
    }
    
    func getRecordUseInfo(id: BigUInt) async throws -> RecordUseInfo {
        try await web3().safe4.accountmanager.getRecordUseInfo(id)
    }
}
