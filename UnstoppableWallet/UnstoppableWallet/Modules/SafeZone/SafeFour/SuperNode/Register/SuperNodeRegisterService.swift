import Foundation
import web3swift
import Web3Core
import EvmKit
import BigInt
import RxSwift
import RxCocoa
import HsExtensions

class SuperNodeRegisterService {
    private let descCountLimit = 12 ... 600
    private let nameCountLimit = 2 ... 20
    private let privateKey: Data
    
    var createMode: CreateMode = .Independent {
        didSet {
            if createMode != oldValue {
                createModeRelay.accept(createMode)
            }
        }
    }

    var balance: Decimal? {
        didSet {
            if balance != oldValue {
                balanceRelay.accept(balance)
            }
        }
    }
    
    var address: String? {
        didSet {
            if address != oldValue {
                addressRelay.accept(address)
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
        
    var superNodeIncentive = SuperNodeIncentive()
    
    private var createModeRelay = BehaviorRelay<CreateMode>(value: .Independent)
    private var balanceRelay = BehaviorRelay<Decimal?>(value: nil)
    private var addressRelay = BehaviorRelay<String?>(value: nil)
    private var nameRelay = BehaviorRelay<String?>(value: nil)
    private var descRelay = BehaviorRelay<String?>(value: nil)
    private var enodeRelay = BehaviorRelay<String?>(value: nil)

    private let balanceCautionRelay = BehaviorRelay<Caution?>(value:nil)
    private let addressCautionRelay = BehaviorRelay<Caution?>(value:nil)
    private var nameCautionRelay = BehaviorRelay<Caution?>(value: nil)
    private let enodeCautionRelay = BehaviorRelay<Caution?>(value:nil)
    private let descCautionRelay = BehaviorRelay<Caution?>(value:nil)
    
    private let evmKit: EvmKit.Kit
    
    init(privateKey: Data, evmKit: EvmKit.Kit) {
        self.privateKey = privateKey
        self.evmKit = evmKit
        sync()
    }
    
    private func web3() async throws -> Web3 {
        let chain = Chain.SafeFourTestNet
        let url = RpcSource.safeFourTestNetRpcHttp().url
        return try await Web3.new( url, network: Networks.Custom(networkID: BigUInt(chain.id)))
    }
    
    private func sync() {
//        self.address = evmKit.receiveAddress.hex
        Task {
            do {
                balance = try await availableBlance()
            }catch{}
        }
    }
}
extension SuperNodeRegisterService {
    
    func availableBlance() async throws -> Decimal? {
        let address = Web3Core.EthereumAddress(evmKit.receiveAddress.hex)!
        let blance = try await web3().eth.getBalance(for: address)
        return blance.safe4ToDecimal()
    }
    
    func exist(address: String) async throws -> Bool {
        let targetAddress = Web3Core.EthereumAddress(address)!
        async let existSuper = try web3().safe4.supernode.exist(targetAddress)
        async let existMaster = try web3().safe4.masternode.exist(targetAddress)
        async let isMasterNodeFounder = try web3().safe4.supernode.existFounder(targetAddress)
        async let isSuperNodeFounder  = try web3().safe4.masternode.existFounder(targetAddress)
        let result = try await (existSuper, existMaster, isMasterNodeFounder, isSuperNodeFounder)
        return result.0 || result.1 || result.2 || result.3
    }
    
    func isValid(address: String) async throws -> Bool {
        let address = Web3Core.EthereumAddress(address)!
        return try await web3().safe4.supernode.isValid(address)
    }
    
    func exist(name: String) async throws -> Bool {
        try await web3().safe4.supernode.existName(name)
    }
    
    func exist(enode: String) async throws -> Bool {
        try await web3().safe4.supernode.existEnode(enode)
    }
    
    func exist(LockID: BigUInt, address: String) async throws -> Bool {
        let address = Web3Core.EthereumAddress(address)!
        return try await web3().safe4.supernode.existLockID(address, LockID)
    }
    
    func create(sendData: SuperNodeSendData) async throws -> String? {
        let amount = BigUInt((createMode.lockAmount * pow(10, safe4Decimals)).hs.roundedString(decimal: 0)) ?? 0
        guard let address, let enode, let desc, let name else{return nil}
        let addr = Web3Core.EthereumAddress(address)!
        let isUnion = createMode == .crowdFunding

        return try await web3().safe4.supernode.register(privateKey: privateKey, value: amount, isUnion: isUnion, addr: addr, lockDay: lockDays, name: name, enode: enode, description: desc, creatorIncentive: superNodeIncentive.creatorIncentive, partnerIncentive: superNodeIncentive.partnerIncentive, voterIncentive: superNodeIncentive.voterIncentive)
    }
    
    
    func isMasterNodeFounder(_ addr: Web3Core.EthereumAddress) async throws -> Bool {
        try await web3().safe4.masternode.existFounder(addr)
    }
    
    func isSuperNodeFounder(_ addr: Web3Core.EthereumAddress) async throws -> Bool {
        try await web3().safe4.supernode.existFounder(addr)
    }
}

extension SuperNodeRegisterService {
    
    var createModeDriver: Driver<CreateMode> {
        createModeRelay.asDriver()
    }
    var balanceDriver: Driver<Decimal?> {
        balanceRelay.asDriver()
    }
    var addressDriver: Driver<String?> {
        addressRelay.asDriver()
    }
    var balanceCautionDriver: Driver<Caution?> {
        balanceCautionRelay.asDriver()
    }
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

    func syncCautionState() -> Bool {
        var caution: Caution? = nil
        
        caution = balanceWarning ? Caution(text: "safe_zone.safe4.account.balance.tips".localized, type: .error) : nil
        balanceCautionRelay.accept(caution)
                        
        caution = descWarning ? Caution(text: "safe_zone.safe4.node.master.input.desc.count.error".localized, type: .error) : nil
        descCautionRelay.accept(caution)
        
        return balanceWarning || descWarning
    }
    
    func validateSuperNodeAddress() async throws -> Bool {
        var caution: Caution? = nil
        guard let address else {
            caution = Caution(text: "safe_zone.safe4.node.super.input.address.tips".localized, type: .error)
            addressCautionRelay.accept(caution)
            return false
        }
        guard isValidAddress(address) else {
            caution = Caution(text: "safe_zone.safe4.node.input.address.error".localized, type: .error)
            addressCautionRelay.accept(caution)
            return false
        }
        guard address.lowercased() != evmKit.receiveAddress.hex.lowercased() else {
            caution = Caution(text: "safe_zone.safe4.node.address.wallet.unuse".localized, type: .error)
            addressCautionRelay.accept(caution)
            return false
        }
        let isExist = try await exist(address: address)
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
    
    func getSendData() -> SuperNodeSendData? {
        guard !syncCautionState() else { return nil }
        guard let name, let address, let enode, let desc else { return nil }
        return SuperNodeSendData(name: name, address: address, ENODE: enode, desc: desc, amount: createMode.lockAmount)
    }
    
}

private extension SuperNodeRegisterService {
    
    var balanceWarning: Bool {
        guard let balance, balance >= createMode.lockAmount else { return true}
        return false
    }
    
    var descWarning: Bool {
        guard let desc, descCountLimit ~= desc.count else { return true}
        return false
    }
    
    func isValidName(text: String) -> Bool {
        return !text.hasPrefix("0x")
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
}

extension SuperNodeRegisterService {
    
    var lockDays: BigUInt {
        720
    }
    
    struct SuperNodeIncentive {
        
        private(set) var createMode: SuperNodeRegisterService.CreateMode = .Independent
        private(set) var partnerIncentive: BigUInt = 45
        private(set) var creatorIncentive: BigUInt = 10
        private(set) var voterIncentive: BigUInt = 45
        private(set) var leftSliderValue: Float = 5
        private(set) var rightSliderValue: Float = 5
        
        let creatorMaxIncentive: Float = 10
        let totalIncentive: Float = 100
        
        var sliderMinimumValue: Float { 0 }
        var sliderMaximumValue: Float { 50 }
                
        var isValid: Bool {
            creatorIncentive + partnerIncentive + voterIncentive == BigUInt(totalIncentive)
        }
        
        mutating func updateLeftSlider(value: Float) {
            leftSliderValue = value
            syncIncentive()
        }
        
        mutating func updateRightSlider(value: Float) {
            rightSliderValue = value
            syncIncentive()
        }
        
        mutating private func syncIncentive() {
            partnerIncentive = BigUInt(sliderMaximumValue - leftSliderValue)
            creatorIncentive = BigUInt(leftSliderValue + rightSliderValue)
            voterIncentive = BigUInt(sliderMaximumValue - rightSliderValue)
        }
    }
    
    enum CreateMode {
        case Independent
        case crowdFunding
        
        var lockAmount: Decimal {
            switch self {
            case .Independent:
                return superNodeRegisterSafeLockNum
            case .crowdFunding:
                return superNodeRegisterSafeLockNum * 0.2 // max * 20%
            }
        }
    }
}

struct SuperNodeSendData {
    let name: String
    let address: String
    let ENODE: String
    let desc: String
    let amount: Decimal
}
