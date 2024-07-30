import Foundation
import web3swift
import Web3Core
import EvmKit
import BigInt
import EvmKit
import RxSwift
import RxCocoa
import HsExtensions

class SuperNodeDetailService {
    private let privateKey: Data
    private let evmKit: EvmKit.Kit

    var balance: Decimal? {
        didSet {
            if balance != oldValue {
                balanceRelay.accept(balance)
            }
        }
    }
    
    private var balanceRelay = BehaviorRelay<Decimal?>(value: nil)

    init(privateKey: Data, evmKit: EvmKit.Kit) {
        self.privateKey = privateKey
        self.evmKit = evmKit
        sync()
    }
    
    private func sync() {
        Task {
            do {
                balance = try await availableBlance()
            }catch{}
        }
    }
    
    private func web3() async throws -> Web3 {
        let chain = Chain.SafeFour
        let url = RpcSource.safeFourRpcHttp().url
        return try await Web3.new( url, network: Networks.Custom(networkID: BigUInt(chain.id)))
    }
}

extension SuperNodeDetailService {
    var balanceDriver: Driver<Decimal?> {
        balanceRelay.asDriver()
    }
}

extension SuperNodeDetailService {
    
    func lastBlockHeight() -> Int? {
        evmKit.lastBlockHeight
    }
    
    func availableBlance() async throws -> Decimal? {
        let address = Web3Core.EthereumAddress(evmKit.receiveAddress.hex)!
        let blance = try await web3().eth.getBalance(for: address)
        return blance.toDecimal(decimals: 18)
    }
    
    func getVoters(address: Web3Core.EthereumAddress, page: Safe4PageControl) async throws -> SNVoteRetInfo {
        try await web3().safe4.snvote.getVoters(address, BigUInt(page.start), BigUInt(page.currentPageCount))
    }
    
    func getVoterNum(address: Web3Core.EthereumAddress) async throws -> BigUInt {
        try await web3().safe4.snvote.getVoterNum(address)
    }
    
    func voteOrApproval(dstAddr: Web3Core.EthereumAddress, recordIDs: [BigUInt]) async throws -> String {
        try await web3().safe4.snvote.voteOrApproval(privateKey: privateKey, isVote: true, dstAddr: dstAddr, recordIDs: recordIDs)
    }

    func voteOrApprovalWithAmount(dstAddr: Web3Core.EthereumAddress, value: BigUInt) async throws -> String {
        return try await web3().safe4.snvote.voteOrApprovalWithAmount(privateKey: privateKey, value: value, isVote: true, dstAddr: dstAddr)
    }

    func getVotedIDNum4Voter() async throws -> BigUInt {
        let address = Web3Core.EthereumAddress(evmKit.receiveAddress.hex)!
        return try await web3().safe4.snvote.getVotedIDNum4Voter(address)
    }
    
    func getVotedIDs4Voter(page: Safe4PageControl) async throws -> [BigUInt] {
        let address = Web3Core.EthereumAddress(evmKit.receiveAddress.hex)!
        return try await web3().safe4.snvote.getVotedIDs4Voter(address, BigUInt(page.start), BigUInt(page.currentPageCount))
    }
    
    func getTotalIDs(page: Safe4PageControl) async throws -> [BigUInt] {
        let address = Web3Core.EthereumAddress(evmKit.receiveAddress.hex)!
        return try await web3().safe4.accountmanager.getTotalIDs(address, BigUInt(page.start), BigUInt(page.currentPageCount))
    }
    
    func getRecordByID(id: BigUInt) async throws -> web3swift.AccountRecord {
        try await web3().safe4.accountmanager.getRecordByID(id)
    }
    
    func appendRegister(value: BigUInt, dstAddr: Web3Core.EthereumAddress) async throws -> String {
        try await web3().safe4.supernode.appendRegister(privateKey: privateKey, value: value, addr: dstAddr, lockDay: 360)
    }
    
    func getRecordUseInfo(id: BigUInt) async throws -> RecordUseInfo {
        try await web3().safe4.accountmanager.getRecordUseInfo(id)
    }
    
    func exist(address: Web3Core.EthereumAddress) async throws -> Bool {
        try await web3().safe4.supernode.exist(address)
    }
}
extension SuperNodeDetailService {
    enum CreateMode {
        case Independent
        case crowdFunding
        
        var lockAmount: BigUInt {
            return  1000 // superNodeRegisterSafeLockNum * 10%
        }
        
        var lockDay: BigUInt {
            360 // appendRegister lock days
        }
    }
}

