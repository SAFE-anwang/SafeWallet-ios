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
    
    func send(data: ProposalSendData) {
        state = .loading
        Task {
            do{
                if let txId = try await service.create(sendData: data) {
                    state = .completed
                }
            }catch {
                state = .failed(error: "safe_zone.safe4.craate.failed".localized)
            }
        }
    }
}

extension ProposalCreateViewModel {
    
    var sendData: ProposalSendData? {
        service.getSendData()
    }
    
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
    
    var startMinimumDate: Date? {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())
        return Calendar.current.startOfDay(for: tomorrow ?? Date())
    }
    
    func endMinimumDate(_ start: Date) -> Date? {
        Calendar.current.date(byAdding: .day, value: 1, to: start)
    }

    
    enum State {
        case loading
        case completed
        case failed(error: String)
    }
        
}
