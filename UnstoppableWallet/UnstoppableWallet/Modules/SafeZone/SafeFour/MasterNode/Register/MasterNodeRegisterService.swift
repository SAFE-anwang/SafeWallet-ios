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
    private let privateKey: Data
    
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
    
    init(privateKey: Data, evmKit: EvmKit.Kit) {
        self.privateKey = privateKey
        self.evmKit = evmKit
        sync()
    }
    
    private func web3() async throws -> Web3 {
        let chain = Chain.SafeFour
        let url = RpcSource.safeFourRpcHttp().url
        return try await Web3.new( url, network: Networks.Custom(networkID: BigUInt(chain.id)))
    }
    
    private func sync() {
        self.address = evmKit.receiveAddress.hex
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
        let address = Web3Core.EthereumAddress(address)!
        return try await web3().safe4.masternode.exist(address)
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
    
    func create() async throws -> String? {
        let amount = BigUInt((createMode.lockAmount * pow(10, safe4Decimals)).hs.roundedString(decimal: 0)) ?? 0
        guard let address, let enode, let desc else{return nil}
        let addr = Web3Core.EthereumAddress(address)!
        return try await web3().safe4.masternode.register(privateKey: privateKey, value: amount, isUnion: false, addr: addr, lockDay: lockDays, enode: enode, description: desc, creatorIncentive: masterNodeIncentive.creatorIncentive, partnerIncentive: masterNodeIncentive.partnerIncentive)
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
        
        caution = balanceWarning ? Caution(text: "账户余额不足以锁仓来创建主节点".localized, type: .error) : nil
        balanceCautionRelay.accept(caution)
        
        caution = descWarning ? Caution(text: "简介信息长度需要大于12且小于600".localized, type: .error) : nil
        descCautionRelay.accept(caution)
        
        return balanceWarning || descWarning
    }
    
    
    func validateSuperNodeAddress() async throws -> Bool {
        var caution: Caution? = nil
        guard let address else {
            caution = Caution(text: "请输入超级节点地址".localized, type: .error)
            addressCautionRelay.accept(caution)
            return false
        }

        guard isValidAddress(address) else {
            caution = Caution(text: "请输入合法的钱包地址".localized, type: .error)
            addressCautionRelay.accept(caution)
            return false
        }
        
        let isExist = try await exist(address: address)
        guard !isExist else {
            let caution = Caution(text: "该地址已被使用".localized, type: .error)
            addressCautionRelay.accept(caution)
            return false
        }
        
        addressCautionRelay.accept(caution)
        return true
    }
    
    func validateSuperNodeEnode() async throws -> Bool {
        var caution: Caution? = nil
        guard let enode else {
            caution = Caution(text: "请输入超级节点ENODE!".localized, type: .error)
            enodeCautionRelay.accept(caution)
            return false
        }
        
        guard isValidEnode(enode) else {
            caution = Caution(text: "超级节点ENODE格式不正确!".localized, type: .error)
            enodeCautionRelay.accept(caution)
            return false
        }
        
        let isExist = try await exist(enode: enode)
        guard !isExist else {
            caution = Caution(text: "该ENODE已被使用".localized, type: .error)
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
    
    var lockDays: BigUInt {
        720
    }
    
    struct MasterNodeIncentive {
        
        private(set) var createMode: MasterNodeRegisterService.CreateMode = .Independent
        private(set) var creatorIncentive: BigUInt = 100
        private(set) var partnerIncentive: BigUInt = 0
        private(set) var sliderValue: Float = 50
        
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
