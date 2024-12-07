import Foundation
import web3swift
import Web3Core
import EvmKit
import BigInt
import RxSwift
import RxCocoa
import HsExtensions

class MasterNodeRegisterService {
    private let descCountLimit = 12 ... 600
    
    var createMode: CreateMode = .Independent {
        didSet {
            if createMode != oldValue {
                masterNodeIncentive.updateMode(createMode)
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
        
    var masterNodeIncentive = MasterNodeIncentive()
    
    private var createModeRelay = BehaviorRelay<CreateMode>(value: .Independent)
    private var balanceRelay = BehaviorRelay<Decimal?>(value: nil)
    private var addressRelay = BehaviorRelay<String?>(value: nil)
    private var descRelay = BehaviorRelay<String?>(value: nil)
    private var enodeRelay = BehaviorRelay<String?>(value: nil)

    private let balanceCautionRelay = BehaviorRelay<Caution?>(value:nil)
    private let addressCautionRelay = BehaviorRelay<Caution?>(value:nil)
    private let enodeCautionRelay = BehaviorRelay<Caution?>(value:nil)
    private let descCautionRelay = BehaviorRelay<Caution?>(value:nil)
    
    private let evmKit: EvmKit.Kit
    private let privateKey: Data
    
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
        Task {
            do {
                balance = try await availableBlance()
            }catch{}
        }
    }
}
extension MasterNodeRegisterService {
    
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
        return try await web3().safe4.masternode.isValid(address)
    }
    
    func exist(enode: String) async throws -> Bool {
        try await web3().safe4.masternode.existEnode(enode)
    }
    
    func exist(LockID: BigUInt, address: String) async throws -> Bool {
        let address = Web3Core.EthereumAddress(address)!
        return try await web3().safe4.masternode.existLockID(address, LockID)
    }
    
    func create(sendData: MasterNodeSendData) async throws -> String? {
        let amount = BigUInt((createMode.lockAmount * pow(10, safe4Decimals)).hs.roundedString(decimal: 0)) ?? 0
        let addr = Web3Core.EthereumAddress(sendData.address)!
        let isUnion = createMode == .crowdFunding
        return try await web3().safe4.masternode.register(privateKey: privateKey, value: amount, isUnion: isUnion, addr: addr, lockDay: lockDays, enode: sendData.ENODE, description: sendData.desc, creatorIncentive: masterNodeIncentive.creatorIncentive, partnerIncentive: masterNodeIncentive.partnerIncentive)
    }
}


extension MasterNodeRegisterService {
    
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
    
    
    func validateMasterNodeAddress() async throws -> Bool {
        var caution: Caution? = nil
        guard let address else {
            caution = Caution(text: "safe_zone.safe4.node.input.address.tips".localized, type: .error)
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
}

private extension MasterNodeRegisterService {
    
    var balanceWarning: Bool {
        guard let balance, balance >= createMode.lockAmount else { return true}
        return false
    }
    
    var descWarning: Bool {
        guard let desc, descCountLimit ~= desc.count else { return true}
        return false
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

extension MasterNodeRegisterService {
    
    func getSendData() -> MasterNodeSendData? {
        guard !syncCautionState() else { return nil }
        guard let address, let enode, let desc else { return nil }
        return MasterNodeSendData(address: address, ENODE: enode, desc: desc, amount: createMode.lockAmount)
    }
    
    var lockDays: BigUInt {
        720
    }
    
    struct MasterNodeIncentive {
        
        private(set) var createMode: MasterNodeRegisterService.CreateMode = .Independent
        private(set) var creatorIncentive: BigUInt = 100
        private(set) var partnerIncentive: BigUInt = 0
        private(set) var sliderValue: Float = 50
        
        let creatorMinIncentive: Float = 1
        let creatorMaxIncentive: Float = 50
        let totalIncentive: Float = 100
        
        var sliderMinimumValue: Float {
            0
        }
        
        var sliderMaximumValue: Float {
            100
        }
                
        var isValid: Bool {
            creatorIncentive + partnerIncentive == BigUInt(totalIncentive)
        }
        
        mutating func updateSlider(value: Float) {
            guard createMode == .crowdFunding else {
                sliderValue = sliderMaximumValue
                updateMode(.Independent)
                return
            }
            sliderValue = value
            updateMode(.crowdFunding)
        }
        
        mutating func updateMode(_ mode: MasterNodeRegisterService.CreateMode) {
            createMode = mode
            switch mode {
            case .Independent:
                creatorIncentive = 100
                partnerIncentive = 0
            case .crowdFunding:
                creatorIncentive = BigUInt(sliderValue)
                partnerIncentive = BigUInt(totalIncentive - sliderValue)
            }
        }
    }
    
    enum CreateMode {
        case Independent
        case crowdFunding
        
        var lockAmount: Decimal {
            switch self {
            case .Independent:
                return masterNodeRegisterSafeLockNum
            case .crowdFunding:
                return masterNodeRegisterSafeLockNum * 0.2
            }
        }
    }
}

struct MasterNodeSendData {
    let address: String
    let ENODE: String
    let desc: String
    let amount: Decimal
}
