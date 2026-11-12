import Foundation
import web3swift
import Web3Core
import EvmKit
import BigInt
import RxSwift
import RxRelay
import RxCocoa

class ProposalDetailService {
    let networkSession = Safe4NetworkSession()

    var cacheScope: Safe4CacheScope {
        Safe4CacheScope(chainId: evmKit.chain.id, owner: address)
    }

    private let evmKit: EvmKit.Kit
    private let privateKey: Data

    var address: String {
        evmKit.receiveAddress.hex
    }

    init(privateKey: Data, evmKit: EvmKit.Kit) {
        self.privateKey = privateKey
        self.evmKit = evmKit
    }

    private func web3() async throws -> Web3 {
        let context = try Safe4Network.activeContext(chainId: evmKit.chain.id)
        try networkSession.check()
        try Task.checkCancellation()
        let web3 = try await Web3.new(context.rpcUrl, network: Networks.Custom(networkID: BigUInt(context.chainId)))
        try networkSession.check()
        try Task.checkCancellation()
        _ = try Safe4Network.activeContext(chainId: context.chainId)
        return web3
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

    func isAbleVote() async throws -> Bool {
        let creatorAddress = Web3Core.EthereumAddress(evmKit.address.hex)!
        let array = try await getTops4Creator(address: creatorAddress)
        return array.count > 0
    }

    func getTops4Creator(address: Web3Core.EthereumAddress) async throws -> [Web3Core.EthereumAddress] {
        try await web3().safe4.supernode.getTops4Creator(address)
    }
    func getInfo(address: Web3Core.EthereumAddress) async throws -> SuperNodeInfo {
        try await web3().safe4.supernode.getInfo(address)
    }
}
