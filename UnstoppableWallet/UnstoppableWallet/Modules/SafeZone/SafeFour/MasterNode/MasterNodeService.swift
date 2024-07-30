import web3swift
import Web3Core
import EvmKit
import BigInt
import RxSwift
import RxCocoa

class MasterNodeService {
    var nodeType: Safe4NodeType = .normal {
        didSet {
            if nodeType != oldValue {
                nodeTypeRelay.accept(nodeType)
            }
        }
    }
    private var nodeTypeRelay = BehaviorRelay<Safe4NodeType>(value: .normal)
    private let evmKit: EvmKit.Kit
    
    init(evmKit: EvmKit.Kit) {
        self.evmKit = evmKit
        sync()
    }
    
    private func sync() {
        let address = evmKit.receiveAddress.hex
        Task {
            do {
                nodeType = try await getNodeType(address: address)
            }catch{}
        }
    }
    
    private func web3() async throws -> Web3 {
        let chain = Chain.SafeFour
        let url = RpcSource.safeFourRpcHttp().url
        return try await Web3.new( url, network: Networks.Custom(networkID: BigUInt(chain.id)))
    }
}

extension MasterNodeService {
    
    var nodeTypeDriver: Driver<Safe4NodeType> {
        nodeTypeRelay.asDriver()
    }
}

extension MasterNodeService {
    
    func getTotalNum() async throws -> BigUInt {
        try await web3().safe4.masternode.getNum()
    }
    
    func superNodeAddressArray(page: Safe4PageControl) async throws -> [ Web3Core.EthereumAddress] {
        try await web3().safe4.masternode.getAll(BigUInt(page.start), BigUInt(page.currentPageCount))
    }
    
    func getInfo(address: Web3Core.EthereumAddress) async throws -> MasterNodeInfo {
        try await web3().safe4.masternode.getInfo(address)
    }
    
    func getNodeType(address: String) async throws ->  Safe4NodeType {
        let address = Web3Core.EthereumAddress(address)!
        async let isMasterNode = try web3().safe4.masternode.exist(address)
        async let isSuperNode = try web3().safe4.supernode.exist(address)
        let nodeType = try await (isMasterNode, isSuperNode)
        if nodeType.0 {
            return .masterNode
        }else if nodeType.1 {
            return .superNode
        }else {
            return .normal
        }
    }
}
