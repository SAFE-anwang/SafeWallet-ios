import Foundation
import web3swift
import Web3Core
import EvmKit
import BigInt
import RxSwift
import RxCocoa
import HsExtensions

class RedeemSafe3Service {
    
    init() {}
    
    private func web3() async throws -> Web3 {
        let chain = Chain.SafeFourTestNet
        let url = RpcSource.safeFourTestNetRpcHttp().url
        return try await Web3.new( url, network: Networks.Custom(networkID: BigUInt(chain.id)))
    }
}
extension RedeemSafe3Service {
    
    func safe3GetAvailableInfo(safe3address: String) async throws -> AvailableSafe3Info {
        try await web3().safe4.safe3.getAvailableInfo(safe3address)
    }
    
    func safe3GetLockedNum(safe3address: String) async throws -> BigUInt {
        try await web3().safe4.safe3.getLockedNum(safe3address)
    }
    
    func safe3GetLockedInfo(safe3address: String, start: BigUInt, count: BigUInt) async throws -> [LockedSafe3Info] {
        try await web3().safe4.safe3.getLockedInfo(safe3address, start, count)
    }
    
    func existAvailableNeedToRedeem(safe3address: String) async throws -> Bool {
        try await web3().safe4.safe3.existAvailableNeedToRedeem(safe3address)
    }
    
    func existLockedNeedToRedeem(safe3Addr: String) async throws -> Bool {
        try await web3().safe4.safe3.existLockedNeedToRedeem(safe3Addr)
    }
    
    func existMasterNodeNeedToRedeem(safe3Addr: String) async throws -> Bool {
        try await web3().safe4.safe3.existMasterNodeNeedToRedeem(safe3Addr)
    }
    
    func redeemSafe3(callerPrivateKey: Data, privateKeys: [Data], targetAddr: String) async throws -> [String] {
        let address = Web3Core.EthereumAddress(targetAddr)!
       return try await web3().safe4.safe3.batchRedeemSafe3(callerPrivateKey: callerPrivateKey, privateKeys: privateKeys, targetAddr: address)
    }

    func redeemMasterNode(callerPrivateKey: Data, privateKeys: [Data], enodes: [String], targetAddr: String) async throws  -> String {
        let address = Web3Core.EthereumAddress(targetAddr)!
        return try await web3().safe4.safe3.batchRedeemMasterNode(callerPrivateKey: callerPrivateKey, privateKeys: privateKeys, enodes: enodes, targetAddr: address)
    }
}
