import web3swift
import Web3Core
import EvmKit
import BigInt
import Foundation

class ProposalService {
    let type: ProposalModule.ProposalType
    
    init(type: ProposalModule.ProposalType) {
        self.type = type
    }
    
    private func web3() async throws -> Web3 {
        let chain = Chain.SafeFourTestNet
        let url = RpcSource.safeFourTestNetRpcHttp().url
        return try await Web3.new( url, network: Networks.Custom(networkID: BigUInt(chain.id)))
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
    
    func proposalIds(page: Safe4PageControl) async throws -> [BigUInt] {
        switch type {
        case .All:
            return try await allProposalIds(page: page)
        case let .Mine(address):
            return try await mineProposalIds(address: address, page: page)
        }
    }
    
    func getInfo(id: BigUInt) async throws -> ProposalInfo {
        try await web3().safe4.proposal.getInfo(id)
    }
    
    func exist(_ id: BigUInt) async throws -> Bool {
        try await web3().safe4.proposal.exist(id)
    }

}

// all Proposal
private extension ProposalService {
    func getNum() async throws -> BigUInt {
        try await web3().safe4.proposal.getNum()
    }
    
    func allProposalIds(page: Safe4PageControl) async throws -> [BigUInt] {
        try await web3().safe4.proposal.getAll(BigUInt(page.start), BigUInt(page.currentPageCount))
    }
    
}

// mine Proposal
private extension ProposalService {
    
    func mineProposalNum(address: String) async throws -> BigUInt {
        let creator = Web3Core.EthereumAddress(address)!
        return try await web3().safe4.proposal.getMineNum(creator)
    }
    
    func mineProposalIds(address: String, page: Safe4PageControl) async throws -> [BigUInt] {
        let creator = Web3Core.EthereumAddress(address)!
        return try await web3().safe4.proposal.getMines(creator, BigUInt(page.start), BigUInt(page.currentPageCount))
    }

}
