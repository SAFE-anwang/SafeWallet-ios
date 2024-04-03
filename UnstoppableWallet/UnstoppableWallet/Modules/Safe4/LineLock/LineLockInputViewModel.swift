import Foundation
import RxSwift
import RxCocoa
import MarketKit

class LineLockInputViewModel {
    private let disposeBag = DisposeBag()
    private let coinRate: Decimal = pow(10, 8)
    private let service: IAmountInputService
    private let decimalParser: AmountDecimalParser
    private let lineLockInputService: LineLockInputService
    
    private var amountRelay = BehaviorRelay<String?>(value: nil)
    private var startMonthRelay = BehaviorRelay<String?>(value: nil)
    private var intervalMonthRelay = BehaviorRelay<String?>(value: nil)
    
    private let maxMonth = 120
    
    init(service: IAmountInputService, decimalParser: AmountDecimalParser, lineLockInputService: LineLockInputService) {
        self.service = service
        self.decimalParser = decimalParser
        self.lineLockInputService = lineLockInputService        
    }

}

extension LineLockInputViewModel {
    
    func isValid(value: String?) -> Bool {
        guard let lockValue = decimalParser.parseAnyDecimal(from: value) else {
            return false
        }
        let isValidCount = lockValue.decimalCount <= 8
        if service.amount > 0, lockValue > 0 {
            let totalAmount = service.amount
            let max = totalAmount / lockValue
            return (0 ... 120 ~= max) && isValidCount
        }
        return isValidCount
    }
    
    func isValid(month: String?) -> Bool {
        guard let month, let monthIntValue = Int(month) else {
            return false
        }
        return  1 ... maxMonth ~= monthIntValue
    }
    
    var amountCautionDriver: Driver<Caution?> {
        lineLockInputService.amountCautionDriver
    }
    
    var startMonthCautionDriver: Driver<Caution?> {
        lineLockInputService.startMonthCautionDriver
    }
    
    var intervalMonthCautionDriver: Driver<Caution?> {
        lineLockInputService.intervalMonthCautionDriver
    }
    
    func equalValue(lhs: String?, rhs: String?) -> Bool {
        let lhsDecimal = decimalParser.parseAnyDecimal(from: lhs) ?? 0
        let rhsDecimal = decimalParser.parseAnyDecimal(from: rhs) ?? 0
        return lhsDecimal == rhsDecimal
    }
    
    var amountDriver: Driver<Decimal?> {
        lineLockInputService.amountDriver
    }
    
    var startMonthDriver: Driver<Int?> {
        lineLockInputService.startMonthDriver
    }
    
    var intervalMonthDriver: Driver<Int?> {
        lineLockInputService.intervalMonthDriver
    }
    
    var lineLockDesDriver: Driver<String?> {
        lineLockInputService.lineLockDesDriver
    }
    
    var lineLockDes: String {
        lineLockInputService.lineLockDes
    }
    
    func onChange(amount: String?) {
        let amount = decimalParser.parseAnyDecimal(from: amount) ?? 0
        lineLockInputService.onChange(amount: amount)
        lineLockInputService.sync(type: .amount)
    }
    
    func onChange(startMonth: String?) {
        lineLockInputService.onChange(startMonth: Int(startMonth ?? "") ?? nil)
        lineLockInputService.sync(type: .startMonth)
    }
    
    func onChange(intervalMonth: String?) {
        lineLockInputService.onChange(intervalMonth: Int(intervalMonth ?? "") ?? nil)
        lineLockInputService.sync(type: .intervalMonth)
    }
}

extension LineLockInputViewModel {

    enum InputType {
        case amount
        case startMonth
        case intervalMonth
    }
}
