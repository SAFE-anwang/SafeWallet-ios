import Foundation
import BigInt
import RxSwift
import RxCocoa

class ProposalCreateViewModel {
    private let service: ProposalCreateService
    private let decimalParser: AmountDecimalParser
    private var stateRelay = PublishRelay<ProposalCreateViewModel.State>()
    
    private(set) var state: ProposalCreateViewModel.State = .loading {
        didSet {
            stateRelay.accept(state)
        }
    }
    
    private var isEnabledSend = true

    init(service: ProposalCreateService, decimalParser: AmountDecimalParser) {
        self.service = service
        self.decimalParser = decimalParser
    }
        
    func onChange(text: String?, type: ProposalInputCell.InputType) {
        switch type {
        case .title:
            service.title = text
        case .desc:
            service.desc = text
        case .safeAmount:
            let amount = decimalParser.parseAnyDecimal(from: text)
            service.amount = amount
        case .payTimes:
            if let text {
                service.payTimes = service.getValidPayTimes(value: Int(text) ?? 0)
            }else {
                service.payTimes = nil
            }
        }
    }

    func send() {
        guard service.syncCautionState() else { return }
        state = .loading
        Task {
            do{
                guard isEnabledSend else { return }
                isEnabledSend = false
                if let txId = try await service.create() {
                    state = .completed
                }
                isEnabledSend = true
            }catch {
                isEnabledSend = true
                state = .failed(error: "创建失败")
            }
        }
    }
}

extension ProposalCreateViewModel {
    
    var balance: String? {
        guard let balance = service.balance else { return "--" }
        return balance.safe4FormattedAmount + " SAFE"
    }
    
    var amount: Decimal? {
        service.amount
    }
    
    var payTimes: Int? {
        service.payTimes
    }
    
    var payType: ProposalCreateService.PayType {
        service.payType
    }
    
    var payTimesDriver: Driver<Int?> {
        service.payTimesDriver
    }

    var payTypeDriver: Driver<ProposalCreateService.PayType> {
        service.payTypeDriver
    }
    
    var balanceDriver: Driver<Decimal?> {
        service.balanceDriver
    }
    var balanceCautionDriver: Driver<Caution?> {
        service.balanceCautionDriver
    }
    var titleCautionDriver: Driver<Caution?> {
        service.titleCautionDriver
    }
    var descCautionDriver: Driver<Caution?> {
        service.descCautionDriver
    }
    var amountCautionDriver: Driver<Caution?> {
        service.amountCautionDriver
    }
    var startPayTimeCautionDriver: Driver<Caution?> {
        service.startPayTimeCautionDriver
    }
    var endPayTimeCautionDriver: Driver<Caution?> {
        service.endPayTimeCautionDriver
    }
    var payTimesCautionDriver: Driver<Caution?> {
        service.payTimesCautionDriver
    }
    
    func update(payType: ProposalCreateService.PayType) {
        service.payType = payType
        switch payType {
        case .all:
            service.payTimes = 1
        case .periodization:
            service.payTimes = 2
        }
    }
    
    func set(startDate: Date?) {
        if let time = startDate?.timeIntervalSince1970 {
            service.startPayTime = BigUInt(time)
        }else {
            service.startPayTime = nil
        }
    }
    
    func set(endDate: Date?) {
        if let time = endDate?.timeIntervalSince1970 {
            service.endPayTime = BigUInt(time)
        }else {
            service.endPayTime = nil
        }
    }
    
    var stateDriver: Observable<ProposalCreateViewModel.State> {
        stateRelay.asObservable()
    }
    
    enum State {
        case loading
        case completed
        case failed(error: String)
    }
    
}
