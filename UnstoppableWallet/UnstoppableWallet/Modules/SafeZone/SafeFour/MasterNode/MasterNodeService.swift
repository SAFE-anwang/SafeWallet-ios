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
        let chain = Chain.SafeFourTestNet
        let url = RpcSource.safeFourTestNetRpcHttp().url
        return try await Web3.new( url, network: Networks.Custom(networkID: BigUInt(chain.id)))
    }
}

extension MasterNodeService {
    
    var receiveAddress: String {
        evmKit.receiveAddress.hex
    }
    
    var address: Web3Core.EthereumAddress {
        Web3Core.EthereumAddress(evmKit.address.hex)!
    }
    
    var nodeTypeDriver: Driver<Safe4NodeType> {
        nodeTypeRelay.asDriver()
    }
    
    func isValidAddress(_ address: String) -> Bool {
        let address = try? EvmKit.Address(hex: address)
        return address != nil
    }
}

extension MasterNodeService {
    
    func getTotalNum() async throws -> BigUInt {
        try await web3().safe4.masternode.getNum()
    }
    
    func masteNodeAddressArray(page: Safe4PageControl) async throws -> [Web3Core.EthereumAddress] {
        try await web3().safe4.masternode.getAll(BigUInt(page.start), BigUInt(page.currentPageCount))
    }
    
    func getInfoByID(_ id: BigUInt) async throws -> MasterNodeInfo {
        try await web3().safe4.masternode.getInfoByID(id)
    }
    
    func getInfo(address: Web3Core.EthereumAddress) async throws -> MasterNodeInfo {
        try await web3().safe4.masternode.getInfo(address)
    }
    
    func isSuperNode(address: Web3Core.EthereumAddress) async throws -> Bool {
        try await web3().safe4.supernode.exist(address)
    }
    
    func isMasterNode(address: Web3Core.EthereumAddress) async throws -> Bool {
        try await web3().safe4.masternode.exist(address)
    }
    
    func getAddrNum4Creator() async throws -> BigUInt {
        let creator = Web3Core.EthereumAddress(evmKit.receiveAddress.hex)!
        return try await web3().safe4.masternode.getAddrNum4Creator(creator)
    }
    
    func getAddrs4Creator(page: Safe4PageControl) async throws -> [Web3Core.EthereumAddress] {
        let creator = Web3Core.EthereumAddress(evmKit.receiveAddress.hex)!
        return try await web3().safe4.masternode.getAddrs4Creator(creator, BigUInt(page.start), BigUInt(page.currentPageCount))
    }
    
    func getAddrNum4Partner(addr: String) async throws -> BigUInt {
        let partner = Web3Core.EthereumAddress(addr)!
        return try await web3().safe4.masternode.getAddrNum4Partner(partner)
    }
    
    func getAddrs4Partner(addr: String, start: BigUInt, count: BigUInt) async throws -> [Web3Core.EthereumAddress] {
        let partner = Web3Core.EthereumAddress(addr)!
        return try await web3().safe4.masternode.getAddrs4Partner(partner, start, count)
    }
    
    func existID(_ id: BigUInt) async throws -> Bool {
        try await web3().safe4.masternode.existID(id)
    }
    
    func exist(_ addr: Web3Core.EthereumAddress) async throws -> Bool {
        try await web3().safe4.masternode.exist(addr)
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
