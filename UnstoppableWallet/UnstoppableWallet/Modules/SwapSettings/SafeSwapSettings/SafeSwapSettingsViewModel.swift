import RxSwift
import RxCocoa

class SafeSwapSettingsViewModel {
    private let disposeBag = DisposeBag()

    private let service: SafeSwapSettingsService
    private let tradeService: SafeSwapTradeService

    private let actionRelay = BehaviorRelay<ActionState>(value: .enabled)

    init(service: SafeSwapSettingsService, tradeService: SafeSwapTradeService) {
        self.service = service
        self.tradeService = tradeService

        service.stateObservable
                .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
                .subscribe(onNext: { [weak self] _ in
                    self?.syncAction()
                })
                .disposed(by: disposeBag)
    }

    private func syncAction() {
        switch service.state {
        case .valid:
            actionRelay.accept(.enabled)
        case .invalid:
            guard let error = service.errors.first else {
                return
            }

            switch error {
            case is SwapSettingsModule.AddressError:
                actionRelay.accept(.disabled(title: "swap.advanced_settings.error.invalid_address".localized))
            case is SwapSettingsModule.SlippageError:
                actionRelay.accept(.disabled(title: "swap.advanced_settings.error.invalid_slippage".localized))
            default: ()
            }
        }
    }

}

extension SafeSwapSettingsViewModel {

    public var actionDriver: Driver<ActionState> {
        actionRelay.asDriver()
    }

    public func doneDidTap() -> Bool {
        if case let .valid(settings) = service.state {
            tradeService.settings = settings
            return true
        }
        return false
    }

}

extension SafeSwapSettingsViewModel {

    enum ActionState {
        case enabled
        case disabled(title: String)
    }

}
