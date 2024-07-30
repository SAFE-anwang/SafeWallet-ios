import web3swift
import Web3Core
import EvmKit
import BigInt
import Foundation

class ProposalService {
    private let type: ProposalModule.ProposalType
    
    init(type: ProposalModule.ProposalType) {
        self.type = type
    }
    
    private func web3() async throws -> Web3 {
        let chain = Chain.SafeFour
        let url = RpcSource.safeFourRpcHttp().url
        return try await Web3.new( url, network: Networks.Custom(networkID: BigUInt(chain.id)))
    }
}

extension ProposalService {    
    func getTotalNum() async throws -> Int {
        switch type {
        case .All:
            let num = try await getNum()
            return Int(num)
            
        case let .Mine(privateKey):
            let num = try await mineProposalNum(privateKey: privateKey)
            return Int(num)
        }
    }
    
    func proposalIds(page: Safe4PageControl) async throws -> [BigUInt] {
        switch type {
        case .All:
            return try await allProposalIds(page: page)
        case let .Mine(privateKey):
            return try await mineProposalIds(privateKey: privateKey, page: page)
        }
    }
    
    func getInfo(id: BigUInt) async throws -> ProposalInfo {
        try await web3().safe4.proposal.getInfo(id)
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
    func mineProposalNum(privateKey: Data) async throws -> BigUInt {
        try await web3().safe4.proposal.getMineNum(privateKey)
    }
    
    func mineProposalIds(privateKey: Data, page: Safe4PageControl) async throws -> [BigUInt] {
        try await web3().safe4.proposal.getMines(privateKey, BigUInt(page.start), BigUInt(page.currentPageCount))
    }
}
