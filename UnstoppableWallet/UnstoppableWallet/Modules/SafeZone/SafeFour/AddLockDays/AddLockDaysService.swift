import web3swift
import Web3Core
import EvmKit
import BigInt
import RxSwift
import RxCocoa
import Foundation
import HsExtensions

class AddLockDaysService {
    private let evmKit: EvmKit.Kit
    private let privateKey: Data

    init(privateKey: Data, evmKit: EvmKit.Kit) {
        self.privateKey = privateKey
        self.evmKit = evmKit
    }
    
    var address: String {
        evmKit.address.hex
    }
    
    var lastBlockHeight: BigUInt? {
        guard let height = evmKit.lastBlockHeight else {return nil}
        return BigUInt(height)
    }
        
    private func web3() async throws -> Web3 {
        let chain = Chain.SafeFourTestNet
        let url = RpcSource.safeFourTestNetRpcHttp().url
        return try await Web3.new( url, network: Networks.Custom(networkID: BigUInt(chain.id)))
    }
    
    func addLock(id: BigUInt, day: BigUInt) async throws -> String {
        try await web3().safe4.accountmanager.addLockDay(privateKey: privateKey, id: id, day: day)
    }
    
    func getRecordByID(id: BigUInt) async throws -> web3swift.AccountRecord {
        try await web3().safe4.accountmanager.getRecordByID(id)
    }
}
