import web3swift
import Foundation
import Web3Core
import EvmKit
import BigInt
import RxSwift
import RxCocoa

class SuperNodeChangeService {

    private let descCountLimit = 12 ... 600
    private let nameCountLimit = 2 ... 20
    
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
    
    var name: String? {
        didSet {
            if name != oldValue {
                nameRelay.accept(name)
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
    private var nameRelay = BehaviorRelay<String?>(value: nil)
    private var descRelay = BehaviorRelay<String?>(value: nil)
    private var enodeRelay = BehaviorRelay<String?>(value: nil)
    
    private let addressCautionRelay = BehaviorRelay<Caution?>(value:nil)
    private var nameCautionRelay = BehaviorRelay<Caution?>(value: nil)
    private let enodeCautionRelay = BehaviorRelay<Caution?>(value:nil)
    private let descCautionRelay = BehaviorRelay<Caution?>(value:nil)
}

extension SuperNodeChangeService {
    
    var addressCautionDriver: Driver<Caution?> {
        addressCautionRelay.asDriver()
    }
    var nameCautionDriver: Driver<Caution?> {
        nameCautionRelay.asDriver()
    }
    var enodeCautionDriver: Driver<Caution?> {
        enodeCautionRelay.asDriver()
    }
    var descCautionDriver: Driver<Caution?> {
        descCautionRelay.asDriver()
    }
    
    func validateSuperNodeAddress(current: String) async throws -> Bool {
        var caution: Caution? = nil
        guard let nodeAddress else {
            caution = Caution(text: "safe_zone.safe4.node.super.input.address.tips".localized, type: .error)
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
    
    func validateSuperNodeName() async throws -> Bool {
        var caution: Caution? = nil

        guard let name, nameCountLimit ~= name.count else {
            caution = Caution(text: "safe_zone.safe4.node.name.count.error".localized, type: .error)
            nameCautionRelay.accept(caution)
            return false
        }
        
        guard isValidName(text: name) else {
            caution = Caution(text: "safe_zone.safe4.node.name.format.error".localized, type: .error)
            nameCautionRelay.accept(caution)
            return false
        }

        
        let isExist = try await exist(name: name)
        guard !isExist else {
            caution = Caution(text: "safe_zone.safe4.node.name.used".localized, type: .error)
            nameCautionRelay.accept(caution)
            return false
        }
        nameCautionRelay.accept(caution)
        return true
    }
    
    func validateSuperNodeEnode() async throws -> Bool {
        var caution: Caution? = nil
        
        guard let enode else {
            caution = Caution(text: "safe_zone.safe4.node.super.input.enode.tips".localized, type: .error)
            enodeCautionRelay.accept(caution)
            return false
        }
        
        guard isValidEnode(enode) else {
            caution = Caution(text: "safe_zone.safe4.node.enode.error".localized, type: .error)
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

    func validateSuperNodeDesc() -> Bool {
        var caution: Caution? = nil

        guard let desc, descCountLimit ~= desc.count else {
            caution = Caution(text: "safe_zone.safe4.node.desc.count.error".localized, type: .error)
            descCautionRelay.accept(caution)
            return false
        }
        descCautionRelay.accept(caution)
        return true

    }
    
    func isValidName(text: String) -> Bool {
        let pattern = "^(?!0x)[a-zA-Z0-9]{2,20}$"
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: text.utf16.count)
        return regex.firstMatch(in: text, options: [], range: range) != nil
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
    
    func setCaution(type: SuperNodeInputType, caution: Caution?) {
        switch type {
        case .address:
            addressCautionRelay.accept(caution)

        case .name:
            nameCautionRelay.accept(caution)

        case .ENODE:
            enodeCautionRelay.accept(caution)

        case .desc:
            descCautionRelay.accept(caution)
        }
    }
}

extension SuperNodeChangeService {
    
    func exist(address: String) async throws -> Bool {
        let targetAddress = Web3Core.EthereumAddress(address)!
        async let existSuper = try web3().safe4.supernode.exist(targetAddress)
        async let existMaster = try web3().safe4.masternode.exist(targetAddress)
        async let isMasterNodeFounder = try web3().safe4.supernode.existFounder(targetAddress)
        async let isSuperNodeFounder  = try web3().safe4.masternode.existFounder(targetAddress)
        let result = try await (existSuper, existMaster, isMasterNodeFounder, isSuperNodeFounder)
        return result.0 || result.1 || result.2 || result.3
    }
    
    func exist(name: String) async throws -> Bool {
        try await web3().safe4.supernode.existName(name)
    }
    
    func exist(enode: String) async throws -> Bool {
        try await web3().safe4.supernode.existEnode(enode)
    }
    
    func changeName(address: Web3Core.EthereumAddress, name: String) async throws -> String {
        return try await web3().safe4.supernode.changeName(privateKey: privateKey, addr: address, name: name)
    }
    
    func changeAddress(address: Web3Core.EthereumAddress, newAddress: String) async throws -> String {
        let newAddress = Web3Core.EthereumAddress(newAddress)!
        return try await web3().safe4.supernode.changeAddress(privateKey: privateKey, addr: address, newAddr: newAddress)
    }
    
    func changeEnode(address: Web3Core.EthereumAddress, enode: String) async throws -> String {
        return try await web3().safe4.supernode.changeEnode(privateKey: privateKey, addr: address, enode: enode)
    }
    
    func changeDescription(address: Web3Core.EthereumAddress, desc: String) async throws -> String {
        return try await web3().safe4.supernode.changeDescription(privateKey: privateKey, addr: address, description: desc)
    }
}
