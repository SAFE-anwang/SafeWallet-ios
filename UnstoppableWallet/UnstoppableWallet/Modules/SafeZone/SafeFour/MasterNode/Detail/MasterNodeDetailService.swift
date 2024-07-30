import Foundation
import web3swift
import Web3Core
import EvmKit
import BigInt
import EvmKit
import RxSwift
import RxCocoa
import HsExtensions

class MasterNodeDetailService {
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

extension MasterNodeDetailService {
    var balanceDriver: Driver<Decimal?> {
        balanceRelay.asDriver()
    }
}

extension MasterNodeDetailService {
    
    func availableBlance() async throws -> Decimal? {
        let address = Web3Core.EthereumAddress(evmKit.receiveAddress.hex)!
        let blance = try await web3().eth.getBalance(for: address)
        return blance.toDecimal(decimals: 18)
    }
    
    func appendRegister(value: BigUInt, dstAddr: Web3Core.EthereumAddress) async throws -> String {
        try await web3().safe4.masternode.appendRegister(privateKey: privateKey, value: value, addr: dstAddr, lockDay: 360)
    }
}
