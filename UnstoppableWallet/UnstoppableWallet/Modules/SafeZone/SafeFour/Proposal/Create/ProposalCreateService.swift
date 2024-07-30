import Foundation
import web3swift
import Web3Core
import EvmKit
import BigInt
import RxSwift
import RxCocoa
import HsExtensions

class ProposalCreateService {
    private let titleCountLimit = 8 ... 80
    private let descCountLimit = 8 ... 600
    private let payTimesLimit = 2 ... 100
    
    private let privateKey: Data

    var balance: Decimal? {
        didSet {
            if balance != oldValue {
                balanceRelay.accept(balance)
            }
        }
    }
    
    var title: String? {
        didSet {
            if title != oldValue {
                titleRelay.accept(title)
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
    
    var amount: Decimal? {
        didSet {
            if amount != oldValue {
                amountRelay.accept(amount)
            }
        }
    }
    
    var payType: PayType = .all {
        didSet {
            if payType != oldValue {
                payTypeRelay.accept(payType)
            }
        }
    }
    
    var startPayTime: BigUInt? {
        didSet {
            if startPayTime != oldValue {
                startPayTimeRelay.accept(startPayTime)
            }
        }
    }
    
    var endPayTime: BigUInt? {
        didSet {
            if endPayTime != oldValue {
                endPayTimeRelay.accept(endPayTime)
            }
        }
    }
    var payTimes: Int? = 1 {
        didSet {
            if payTimes != oldValue {
                payTimesRelay.accept(payTimes)
            }
        }
    }
    private var balanceRelay = BehaviorRelay<Decimal?>(value: nil)
    private var titleRelay = BehaviorRelay<String?>(value: nil)
    private var descRelay = BehaviorRelay<String?>(value: nil)
    private var amountRelay = BehaviorRelay<Decimal?>(value: nil)
    private var payTypeRelay = BehaviorRelay<PayType>(value: .all)
    private var startPayTimeRelay = BehaviorRelay<BigUInt?>(value: nil)
    private var endPayTimeRelay = BehaviorRelay<BigUInt?>(value: nil)
    private var payTimesRelay = BehaviorRelay<Int?>(value: nil)
    
    private let balanceCautionRelay = BehaviorRelay<Caution?>(value:nil)
    private let titleCautionRelay = BehaviorRelay<Caution?>(value:nil)
    private let descCautionRelay = BehaviorRelay<Caution?>(value:nil)
    private let amountCautionRelay = BehaviorRelay<Caution?>(value:nil)
    private let startPayTimeCautionRelay = BehaviorRelay<Caution?>(value:nil)
    private let endPayTimeCautionRelay = BehaviorRelay<Caution?>(value:nil)
    private let payTimesCautionRelay = BehaviorRelay<Caution?>(value: nil)

    init(privateKey: Data) {
        self.privateKey = privateKey
        Task {
            do{
                _ = try await pollBalance()
            }catch{
                
            }
        }
    }
    
    private func web3() async throws -> Web3 {
        let chain = Chain.SafeFour
        let url = RpcSource.safeFourRpcHttp().url
        return try await Web3.new( url, network: Networks.Custom(networkID: BigUInt(chain.id)))
    }
}
extension ProposalCreateService {
    func getVoterNum(id: BigUInt) async throws -> BigUInt {
        try await web3().safe4.proposal.getVoterNum(id)
    }
    
    func pollBalance() async throws -> BigUInt {
        let balance = try await web3().safe4.proposal.getBalance()
        self.balance = Decimal(bigUInt: balance, decimals: safe4Decimals)
        return balance
    }
    
    func create() async throws -> String? {
        guard let title, let payTimes, let startPayTime, let endPayTime, let desc, let amount else{return nil}
        let payAmount = BigUInt((amount * pow(10, safe4Decimals)).hs.roundedString(decimal: 0)) ?? 0
        return try await web3().safe4.proposal.create(privateKey: privateKey, title: title, payAmount: payAmount, payTimes: BigUInt(payTimes), startPayTime: startPayTime, endPayTime: endPayTime, description: desc)
    }
}

extension ProposalCreateService {
    
    var balanceDriver: Driver<Decimal?> {
        balanceRelay.asDriver()
    }
    var payTypeDriver: Driver<PayType> {
        payTypeRelay.asDriver()
    }
    var payTimesDriver: Driver<Int?> {
        payTimesRelay.asDriver()
    }
    var balanceCautionDriver: Driver<Caution?> {
        balanceCautionRelay.asDriver()
    }
    var titleCautionDriver: Driver<Caution?> {
        titleCautionRelay.asDriver()
    }
    var descCautionDriver: Driver<Caution?> {
        descCautionRelay.asDriver()
    }
    var amountCautionDriver: Driver<Caution?> {
        amountCautionRelay.asDriver()
    }
    var startPayTimeCautionDriver: Driver<Caution?> {
        startPayTimeCautionRelay.asDriver()
    }
    var endPayTimeCautionDriver: Driver<Caution?> {
        endPayTimeCautionRelay.asDriver()
    }
    var payTimesCautionDriver: Driver<Caution?> {
        payTimesCautionRelay.asDriver()
    }
    
    func syncCautionState() -> Bool {
        var caution: Caution? = nil
        
        caution = balanceWarning ? Caution(text: "资金池余额获取失败".localized, type: .error) : nil
        balanceCautionRelay.accept(caution)
        
        caution = titleWarning ? Caution(text: "标题长度需要大于8且小于80".localized, type: .error) : nil
        titleCautionRelay.accept(caution)
        
        caution = descWarning ? Caution(text: "描述长度需要大于8且小于600".localized, type: .error) : nil
        descCautionRelay.accept(caution)
        
        caution = amountWarning ? Caution(text: "输入有效的SAFE数量".localized, type: .error) : nil
        amountCautionRelay.accept(caution)

        caution = payTimesWarning ? Caution(text: "分期次数为2至100".localized, type: .error) : nil
        payTimesCautionRelay.accept(caution)

        let startCaution = startPayTimeWarning
        startPayTimeCautionRelay.accept(startCaution)
        
        if case .all = payType {
            endPayTime = startPayTime
            payTimes = 1
        }
        let endCaution = endPayTimeWarning
        endPayTimeCautionRelay.accept(endCaution)
        
        return !(balanceWarning && titleWarning && descWarning && amountWarning && payTimesWarning)  && startCaution == nil && endCaution == nil
    }
    
    func getValidPayTimes(value: Int) -> Int {
        switch payType {
        case .all:
            return 1
        case .periodization:
            if value < 2 {
                return 2
            }else if value > 100 {
                return 100
            }else {
                return value
            }
        }
    }
}

private extension ProposalCreateService {
    
    var balanceWarning: Bool {
        guard balance != nil else { return true}
        return false
    }
    
    var titleWarning: Bool {
        guard let title, titleCountLimit ~= title.count else { return true}
        return false
    }
    
    var descWarning: Bool {
        guard let desc, descCountLimit ~= desc.count else { return true}
        return false
    }
    
    var amountWarning: Bool {
        guard let amount, let balance, amount > 0, amount <= balance  else { return true}
        return false
    }
   
    var startPayTimeWarning: Caution? {
        guard let startPayTime else { return Caution(text: "请选择付款日期".localized, type: .error)}
        guard startPayTime > BigUInt(Date().timeIntervalSince1970) else { return Caution(text: "付款日期需大于当前时间".localized, type: .error)}
        return nil
    }
    
    var endPayTimeWarning: Caution? {
        guard  let endPayTime else { return Caution(text: "请选择结束时间".localized, type: .error)}
        guard let startPayTime, endPayTime >= startPayTime else { return Caution(text: "结束时间应该大于开始时间".localized, type: .error)}
        return nil
    }
    
    var payTimesWarning: Bool {
        switch payType {
        case .all:
            guard let payTimes, payTimes == 1 else { return true}
            return false
        case .periodization:
            guard let payTimes, payTimesLimit ~= payTimes else { return true}
            return false
        }
    }
}

extension ProposalCreateService {
    enum PayType {
        case all
        case periodization
    }
}
