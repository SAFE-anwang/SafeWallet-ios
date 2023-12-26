
import Foundation
import RxSwift
import RxCocoa

class LiquidityAllowanceViewModel {
    private let disposeBag = DisposeBag()

    private let allowanceService: LiquidityAllowanceService
    private let pendingAllowanceService: LiquidityPendingAllowanceService

    private(set) var isVisible: Bool = false {
        didSet {
            isVisibleRelay.accept(isVisible)
        }
    }
    private var isVisibleRelay = PublishRelay<Bool>()
    private var allowanceRelay = BehaviorRelay<String?>(value: nil)
    private var isErrorRelay = BehaviorRelay<Bool>(value: false)

    init(errorProvider: ISwapErrorProvider, allowanceService: LiquidityAllowanceService, pendingAllowanceService: LiquidityPendingAllowanceService) {
        self.allowanceService = allowanceService
        self.pendingAllowanceService = pendingAllowanceService
        
        syncVisible()

        subscribe(disposeBag, Observable.combineLatest(allowanceService.stateObservable, errorProvider.errorsObservable)) { [weak self] in self?.handle(allowanceState: $0, errors: $1) }
        subscribe(disposeBag, errorProvider.errorsObservable) { [weak self] in self?.handle(errors: $0) }
    }

    private func syncVisible(allowanceState: LiquidityAllowanceService.State? = nil) {
        
        
        guard let state = allowanceService.state  else {
            isVisible = false
            return
        }

        guard pendingAllowanceService.state != .pending else {
            isVisible = true
            return
        }
        switch state {
        case .notReady: isVisible = true
        default: isVisible = isErrorRelay.value
        }

    }

    private func handle(allowanceState: LiquidityAllowanceService.State?, errors: [Error]) {
        syncVisible(allowanceState: allowanceState)

        if let state = allowanceService.state {
            allowanceRelay.accept(allowance(state: state, errors: errors))
        } else {
            allowanceRelay.accept(nil)
        }
    }

    private func handle(errors: [Error]) {
        let errorA = errors.first(where: { .insufficientAllowance == $0 as? SwapModule.SwapError })
        let errorB = errors.first(where: { .insufficientAllowanceB == $0 as? SwapModule.SwapError })
        isErrorRelay.accept(errorA != nil && errorB != nil )

        syncVisible()
    }

    private func allowance(state: LiquidityAllowanceService.State, errors: [Error]) -> String? {
        let isInsufficientAllowanceA = errors.first(where: { .insufficientAllowance == $0 as? SwapModule.SwapError }) != nil
        let isInsufficientAllowanceB = errors.first(where: { .insufficientAllowanceB == $0 as? SwapModule.SwapError }) != nil
        switch state {
        case .ready(let allowanceA, let allowanceB):
            let valueFormatterA = isInsufficientAllowanceA ? ValueFormatter.instance.formatFull(coinValue: allowanceA) : nil
            let valueFormatterB = isInsufficientAllowanceB ? ValueFormatter.instance.formatFull(coinValue: allowanceB) : nil
            return (valueFormatterA != nil) ? valueFormatterA : valueFormatterB
        default: return nil
        }
    }

}

extension LiquidityAllowanceViewModel {

    var isVisibleSignal: Signal<Bool> {
        isVisibleRelay.asSignal()
    }

    var allowanceDriver: Driver<String?> {
        allowanceRelay.asDriver()
    }

    var isErrorDriver: Driver<Bool> {
        isErrorRelay.asDriver()
    }

}
