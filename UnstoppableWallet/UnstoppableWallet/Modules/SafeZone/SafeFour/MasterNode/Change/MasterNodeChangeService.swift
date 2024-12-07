import web3swift
import Foundation
import Web3Core
import EvmKit
import BigInt
import RxSwift
import RxCocoa

class MasterNodeChangeService {

    private let descCountLimit = 12 ... 600
    
    private let evmKit: EvmKit.Kit
    private let privateKey: Data

    init(privateKey: Data, evmKit: EvmKit.Kit) {
        self.privateKey = privateKey
        self.evmKit = evmKit
    }
    
    private func web3() async throws -> Web3 {
        let chain = Chain.SafeFourTestNet
        let url = RpcSource.safeFourTestNetRpcHttp().url
        return try await Web3.new( url, network: Networks.Custom(networkID: BigUInt(chain.id)))
    }
    
    var nodeAddress: String? {
        didSet {
            if nodeAddress != oldValue {
                addressRelay.accept(nodeAddress)
            }
        }
    }
    
    var enode: String? {
        didSet {
            if enode != oldValue {
                enodeRelay.accept(enode)
            }
        }
    }
    
    var desc: String? {
        didSet {
            if desc != oldValue {
                descRelay.accept(desc)
            }
        }
    }
    private var addressRelay = BehaviorRelay<String?>(value: nil)
    private var descRelay = BehaviorRelay<String?>(value: nil)
    private var enodeRelay = BehaviorRelay<String?>(value: nil)
    
    private let addressCautionRelay = BehaviorRelay<Caution?>(value:nil)
    private let enodeCautionRelay = BehaviorRelay<Caution?>(value:nil)
    private let descCautionRelay = BehaviorRelay<Caution?>(value:nil)
}

extension MasterNodeChangeService {
    
    var addressCautionDriver: Driver<Caution?> {
        addressCautionRelay.asDriver()
    }

    var enodeCautionDriver: Driver<Caution?> {
        enodeCautionRelay.asDriver()
    }
    var descCautionDriver: Driver<Caution?> {
        descCautionRelay.asDriver()
    }
    
    func validateMasterNodeAddress() async throws -> Bool {
        var caution: Caution? = nil
        guard let nodeAddress else {
            caution = Caution(text: "safe_zone.safe4.node.input.address.tips".localized, type: .error)
            addressCautionRelay.accept(caution)
            return false
        }
        guard isValidAddress(nodeAddress) else {
            caution = Caution(text: "safe_zone.safe4.node.input.address.error".localized, type: .error)
            addressCautionRelay.accept(caution)
            return false
        }
        
        guard nodeAddress.lowercased() != evmKit.receiveAddress.hex.lowercased() else {
            caution = Caution(text: "safe_zone.safe4.node.address.wallet.unuse".localized, type: .error)
            addressCautionRelay.accept(caution)
            return false
        }

        let isExist = try await exist(address: nodeAddress)
        guard !isExist else {
            let caution = Caution(text: "safe_zone.safe4.node.input.address.used".localized, type: .error)
            addressCautionRelay.accept(caution)
            return false
        }
        
        addressCautionRelay.accept(caution)
        return true
    }

    func validateMasterNodeEnode() async throws -> Bool {
        var caution: Caution? = nil
        
        guard let enode else {
            caution = Caution(text: "safe_zone.safe4.node.master.input.endoe.tips".localized, type: .error)
            enodeCautionRelay.accept(caution)
            return false
        }
        
        guard isValidEnode(enode) else {
            caution = Caution(text: "safe_zone.safe4.node.master.input.endoe.error".localized, type: .error)
            enodeCautionRelay.accept(caution)
            return false
        }
        
        let isExist = try await exist(enode: enode)
        guard !isExist else {
            caution = Caution(text: "safe_zone.safe4.node.master.input.endoe.used".localized, type: .error)
            enodeCautionRelay.accept(caution)
            return false
        }
        enodeCautionRelay.accept(caution)
        return true
    }

    func validateMasterNodeDesc() -> Bool {
        var caution: Caution? = nil

        guard let desc, descCountLimit ~= desc.count else {
            caution = Caution(text: "safe_zone.safe4.node.master.input.desc.count.error".localized, type: .error)
            descCautionRelay.accept(caution)
            return false
        }
        descCautionRelay.accept(caution)
        return true

    }

    func isValidAddress(_ address: String) -> Bool {
        let address = try? EvmKit.Address(hex: address)
        return address != nil
    }
    
    func isValidEnode(_ enode: String) -> Bool {
        let enodeRegex = "^enode://[0-9a-fA-F]{128}@[0-9.]+:[0-9]+$"
        let enodeTest = NSPredicate(format:"SELF MATCHES %@", enodeRegex)
        return enodeTest.evaluate(with: enode)
    }
    
    func setCaution(type: MasterNodeInputType, caution: Caution?) {
        switch type {
        case .address:
            addressCautionRelay.accept(caution)

        case .ENODE:
            enodeCautionRelay.accept(caution)

        case .desc:
            descCautionRelay.accept(caution)
        }
    }
}

extension MasterNodeChangeService {
    
    func exist(address: String) async throws -> Bool {
//        let address = Web3Core.EthereumAddress(address)!
//        return try await web3().safe4.masternode.exist(address)
        let targetAddress = Web3Core.EthereumAddress(address)!
        async let existSuper = try web3().safe4.supernode.exist(targetAddress)
        async let existMaster = try web3().safe4.masternode.exist(targetAddress)
        async let isMasterNodeFounder = try web3().safe4.supernode.existFounder(targetAddress)
        async let isSuperNodeFounder  = try web3().safe4.masternode.existFounder(targetAddress)
        let result = try await (existSuper, existMaster, isMasterNodeFounder, isSuperNodeFounder)
        return result.0 || result.1 || result.2 || result.3
    }

    func exist(enode: String) async throws -> Bool {
        try await web3().safe4.masternode.existEnode(enode)
    }
    
    func changeAddress(address: Web3Core.EthereumAddress, newAddress: String) async throws -> String {
        let newAddress = Web3Core.EthereumAddress(newAddress)!
        return try await web3().safe4.masternode.changeAddress(privateKey: privateKey, addr: address, newAddr: newAddress)
    }
    
    func changeEnode(address: Web3Core.EthereumAddress, enode: String) async throws -> String {
        return try await web3().safe4.masternode.changeEnode(privateKey: privateKey, addr: address, enode: enode)
    }
    
    func changeDescription(address: Web3Core.EthereumAddress, desc: String) async throws -> String {
        return try await web3().safe4.masternode.changeDescription(privateKey: privateKey, addr: address, description: desc)
    }
}

