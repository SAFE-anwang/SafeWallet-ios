import Foundation
import web3swift
import Web3Core
import EvmKit
import BigInt
import RxSwift
import RxRelay
import RxCocoa

class ProposalDetailService {
    
    private let evmKit: EvmKit.Kit
    private let privateKey: Data
    
    var address: String {
        evmKit.receiveAddress.hex
    }
    
    var isAbleVote: Bool = false {
        didSet {
            if isAbleVote != oldValue {
                isAbleVoteRelay.accept(isAbleVote)
            }
        }
    }
    
    private var isAbleVoteRelay = BehaviorRelay<Bool>(value: false)
    
    init(privateKey: Data, evmKit: EvmKit.Kit) {
        self.privateKey = privateKey
        self.evmKit = evmKit
    }

    private func web3() async throws -> Web3 {
        let chain = Chain.SafeFour
        let url = RpcSource.safeFourRpcHttp().url
        return try await Web3.new( url, network: Networks.Custom(networkID: BigUInt(chain.id)))
    }
}
extension ProposalDetailService {
    
    var isAbleVoteDriver: Driver<Bool> {
        isAbleVoteRelay.asDriver()
    }
}
extension ProposalDetailService {
    
    func vote(id: BigUInt, voteResult: BigUInt) async throws -> String {
        try await web3().safe4.proposal.vote(privateKey: privateKey, id: id, voteResult: voteResult)
    }
    
    func getVoterNum(id: BigUInt) async throws -> BigUInt {
        try await web3().safe4.proposal.getVoterNum(id)
    }
    
    func getVoteInfo(id: BigUInt, page: Safe4PageControl) async throws -> [ProposalVoteInfo] {
        try await web3().safe4.proposal.getVoteInfo(id, BigUInt(page.start), BigUInt(page.currentPageCount))
    }
    
    func getTops() async throws -> [Web3Core.EthereumAddress] {
        try await web3().safe4.supernode.getTops()
    }
    
    func isAbleVote() async throws {
        let addressArray = try await getTops()
        let isContains = addressArray.map{$0.address.lowercased()}.contains(address.lowercased())
        isAbleVote = isContains
    }
}

