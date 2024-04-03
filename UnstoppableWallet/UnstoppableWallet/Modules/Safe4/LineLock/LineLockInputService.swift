import Foundation
import RxSwift
import RxCocoa
import MarketKit
import BitcoinCore
import HsToolKit

class LineLockInputService {
    
    private let maxMonth = 120

    var amount: Decimal? {
        didSet {
            if amount != oldValue {
                amountRelay.accept(amount)
            }
        }
    }
    
    var startMonth: Int? {
        didSet {
            if startMonth != oldValue {
                startMonthRelay.accept(startMonth)
            }
        }
    }
    
    var intervalMonth: Int? {
        didSet {
            if intervalMonth != oldValue {
                intervalMonthRelay.accept(intervalMonth)
            }
        }
    }
    
    private let disposeBag = DisposeBag()
    
    private var amountRelay = BehaviorRelay<Decimal?>(value: nil)
    private var startMonthRelay = BehaviorRelay<Int?>(value: nil)
    private var intervalMonthRelay = BehaviorRelay<Int?>(value: nil)
    
    private let service: IAmountInputService
    
    private var lineLockDesRelay = BehaviorRelay<String?>(value: nil)

    private let amountCautionRelay = BehaviorRelay<Caution?>(value:nil)
    private let startMonthCautionRelay = BehaviorRelay<Caution?>(value:nil)
    private let intervalMonthCautionRelay = BehaviorRelay<Caution?>(value:nil)

    private let stateRelay = PublishRelay<SendBaseService.State>()
    private(set) var state: SendBaseService.State = .notReady {
        didSet {
            stateRelay.accept(state)
        }
    }

    init(service: IAmountInputService, fiatService: FiatService) {
        self.service = service
        
        subscribe(disposeBag, service.amountObservable) { [weak self] in self?.sync(amount: $0) }
        sync(amount: service.amount)
    }
    
    func sync(amount: Decimal) {
        
        if self.amount == nil {
            self.amount = amount > 0 ? min( amount, 1) : nil
        }
        
        if self.startMonth == nil {
            self.startMonth = 1
        }
        
        if self.intervalMonth == nil {
            self.intervalMonth = 1
        }
        sync(type: .amount)
        syncState()
    }
    
    func sync(type: LineLockInputViewModel.InputType) {
        var caution: Caution? = nil
        
        switch type {
        case .amount:
            if amountWarning {
                caution = Caution(text: "safe_lock.amount.unlock.error".localized, type: .error)
            }
            amountCautionRelay.accept(caution)
        case .startMonth:
            if startMonthWarning {
               caution = Caution(text: "safe_lock.amount.error".localized, type: .error)
            }
            startMonthCautionRelay.accept(caution)
        case .intervalMonth:
            if intervalMonthWarning {
               caution = Caution(text: "safe_lock.amount.error".localized, type: .error)
            }
            intervalMonthCautionRelay.accept(caution)
        }
    }
    
    private func syncState() {
        lineLockDesRelay.accept(lineLockDes)

        guard let amount, amount > 0 else {
            state = .notReady
            return
        }
        
        if amountWarning {
            state = .notReady
            return
        }
        
        if startMonthWarning {
            state = .notReady
            return
        }

        if intervalMonthWarning {
            state = .notReady
            return
        }

        state = .ready
    }
}

extension LineLockInputService {
    
    var amountDriver: Driver<Decimal?> {
        amountRelay.asDriver()
    }
    
    var startMonthDriver: Driver<Int?> {
        startMonthRelay.asDriver()
    }
    
    var intervalMonthDriver: Driver<Int?> {
        intervalMonthRelay.asDriver()
    }
    
    var lineLockDesDriver: Driver<String?> {
        lineLockDesRelay.asDriver()
    }
    
    var amountCautionDriver: Driver<Caution?> {
        amountCautionRelay.asDriver()
    }
    
    var startMonthCautionDriver: Driver<Caution?> {
        startMonthCautionRelay.asDriver()
    }
    
    var intervalMonthCautionDriver: Driver<Caution?> {
        intervalMonthCautionRelay.asDriver()
    }
    
    func onChange(amount: Decimal?) {
        self.amount = amount
        syncState()
    }
    
    func onChange(startMonth: Int?) {
        self.startMonth = startMonth
        syncState()
    }
    
    func onChange(intervalMonth: Int?) {
        self.intervalMonth = intervalMonth
        syncState()
    }
    
    var amountWarning: Bool {
        if let amount {
            guard amount <= service.amount else { return true}
            return false
        }else {
            return false
        }
    }
    
    var startMonthWarning: Bool {
        guard let startMonth, 1...maxMonth ~= startMonth else { return true}
        return false
    }
    
    var intervalMonthWarning: Bool {
        guard let intervalMonth, 1...maxMonth ~= intervalMonth else { return true}
        return false
    }
    
    var stateObservable: Observable<SendBaseService.State> {
        stateRelay.asObservable()
    }
    
    // fiatService.set(amount: amount)
    
    var totalLockedAmount: Decimal {
        guard let lockedValue = amount, let startMonth, let intervalMonth else { return 0}
        
        let max = decimalNumberToInt(value: service.amount/lockedValue)
        let outputSize = checkMaxInterval(outputSize: max, startMonth: startMonth, intervalMonth: intervalMonth)
        let totalAmount = lockedValue * Decimal(outputSize)
        
        return totalAmount
    }
    
    var lineLockDes: String {
        guard let lockedValue = amount, let startMonth, let intervalMonth else { return ""}
        return "safe_lock.desc".localized(startMonth , intervalMonth , "\(lockedValue)", "\(totalLockedAmount)")
    }
    
    func getLineLockInfo(coinAmount: Decimal, lockedValue: Decimal, startMonth: Int, intervalMonth: Int) -> (Decimal, String) {
        let max = decimalNumberToInt(value: service.amount/lockedValue)
        let outputSize = checkMaxInterval(outputSize: max, startMonth: startMonth, intervalMonth: intervalMonth)
        let lineLock = LineLock(lastHeight: 0, lockedValue: "\(lockedValue)", startMonth: startMonth, intervalMonth: intervalMonth, outputSize: outputSize)
        let totalAmount = lockedValue * Decimal(outputSize)
        return (totalAmount, lineLock.reverseHex())
    }

    private func checkMaxInterval(outputSize: Int, startMonth: Int, intervalMonth: Int) -> Int {
        var maxOutputSize = outputSize
        for index in 0 ... outputSize {
            maxOutputSize = index
            let nextMonth = startMonth + intervalMonth * index
            if (nextMonth > maxMonth) {
                break
            }
        }
        return maxOutputSize
    }
    
    private func decimalNumberToInt(value: Decimal) -> Int {
        let handler = NSDecimalNumberHandler(roundingMode: .down, scale: Int16(truncatingIfNeeded: 0), raiseOnExactness: false, raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false)
        return NSDecimalNumber(decimal: value).rounding(accordingToBehavior: handler).intValue
    }

}

