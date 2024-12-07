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
        let chain = Chain.SafeFourTestNet
        let url = RpcSource.safeFourTestNetRpcHttp().url
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
    
    func create(sendData: ProposalSendData) async throws -> String? {
        let payAmount = BigUInt((sendData.amount * pow(10, safe4Decimals)).hs.roundedString(decimal: 0)) ?? 0
        return try await web3().safe4.proposal.create(privateKey: privateKey, title: sendData.title, payAmount: payAmount, payTimes: BigUInt(sendData.payTimes), startPayTime: sendData.startPayTime, endPayTime: sendData.endPayTime, description: sendData.desc)
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
    var payTimesCautionDriver: Driver<Caution?> {
        payTimesCautionRelay.asDriver()
    }
        
    func getValidPayTimes(value: Int) -> Int {
        let maxTimes = 100
        switch payType {
        case .all:
            return 1
        case .periodization:
            return min(max(2, value), maxTimes)
        }
    }
    
    func getSendData() -> ProposalSendData? {
        guard !syncCautionState() else { return nil }
        guard let title, let desc, let amount, let startPayTime, let endPayTime, let payTimes else { return nil }
        return ProposalSendData(title: title, desc: desc, amount: amount, startPayTime: startPayTime, endPayTime: endPayTime, payTimes: payTimes)
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
        guard let startPayTime else { return Caution(text: "safe_zone.safe4.pay.time.choose".localized, type: .error)}
        guard startPayTime > BigUInt(Date().timeIntervalSince1970) else { return Caution(text: "safe_zone.safe4.date.payment.error".localized, type: .error)}
        guard  let endPayTime else { return Caution(text: "safe_zone.safe4.time.end.choose".localized, type: .error)}
        guard endPayTime >= startPayTime else { return Caution(text: "safe_zone.safe4.time.end.error".localized, type: .error)}
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
    
    func syncCautionState() -> Bool {
        var caution: Caution? = nil
        
        caution = balanceWarning ? Caution(text: "safe_zone.safe4.pool.balance.error".localized, type: .error) : nil
        balanceCautionRelay.accept(caution)
        
        caution = titleWarning ? Caution(text: "safe_zone.safe4.proposal.title.count.error".localized, type: .error) : nil
        titleCautionRelay.accept(caution)
        
        caution = descWarning ? Caution(text: "safe_zone.safe4.proposal.desc.count.error".localized, type: .error) : nil
        descCautionRelay.accept(caution)
        
        caution = amountWarning ? Caution(text: "safe_zone.safe4.proposal.input.safe.error".localized, type: .error) : nil
        amountCautionRelay.accept(caution)

        caution = payTimesWarning ? Caution(text: "safe_zone.safe4.proposal.instalment.number.titps".localized, type: .error) : nil
        payTimesCautionRelay.accept(caution)
        
        if case .all = payType {
            endPayTime = startPayTime
            payTimes = 1
        }
        let startCaution = startPayTimeWarning
        startPayTimeCautionRelay.accept(startCaution)
        
        return balanceWarning || titleWarning || descWarning || amountWarning || payTimesWarning || startCaution != nil
    }
}

extension ProposalCreateService {
    enum PayType {
        case all
        case periodization
    }
}

struct ProposalSendData {
    let title: String
    let desc: String
    let amount: Decimal
    let startPayTime: BigUInt
    let endPayTime: BigUInt
    let payTimes: Int
    
    var payTypeDesc: String {
        let start = Date(timeIntervalSince1970: Double(startPayTime))
        let startDate = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? Date()// next day
        let payDate = DateHelper().safe4Format(date: startDate)

        if payTimes < 2 {
            return "safe_zone.safe4.pay.method.disposabl.desc".localized("\(payDate)", "\(amount)")
        }else {
            let endDate = Date(timeIntervalSince1970: Double(endPayTime))
            let end = endPayTime == startPayTime ? payDate : DateHelper().safe4Format(date: endDate)
            return "safe_zone.safe4.pay.method.instalment.desc".localized("\(payDate)", "\(end)", "\(payTimes)", "\(amount)")
        }
    }
}
