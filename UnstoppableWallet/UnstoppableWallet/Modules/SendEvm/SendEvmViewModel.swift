import EvmKit
import Foundation
import MarketKit
import RxCocoa
import RxSwift
import Hodler

class SendEvmViewModel {
    private let service: SendEvmService
    private let disposeBag = DisposeBag()

    private let proceedEnabledRelay = BehaviorRelay<Bool>(value: false)
    private let amountCautionRelay = BehaviorRelay<Caution?>(value: nil)
    private let proceedRelay = PublishRelay<SendEvmData>()
    private let timeLockService: TimeLockService?
    
    init(service: SendEvmService, timeLockService: TimeLockService? = nil) {
        self.service = service
        self.timeLockService = timeLockService
        
        subscribe(disposeBag, service.stateObservable) { [weak self] in self?.sync(state: $0) }
        subscribe(disposeBag, service.amountCautionObservable) { [weak self] in self?.sync(amountCaution: $0) }
        subscribe(disposeBag, timeLockService?.pluginDataObservable) { [weak self] in self?.sync(pluginData: $0) }
        
        sync(state: service.state)
    }

    private func sync(state: SendEvmService.State) {
        if case .ready = state {
            proceedEnabledRelay.accept(true)
        } else {
            proceedEnabledRelay.accept(false)
        }
    }

    private func sync(amountCaution: (error: Error?, warning: SendEvmService.AmountWarning?)) {
        var caution: Caution?

        if let error = amountCaution.error {
            caution = Caution(text: error.smartDescription, type: .error)
        } else if let warning = amountCaution.warning {
            switch warning {
            case .coinNeededForFee: caution = Caution(text: "send.amount_warning.coin_needed_for_fee".localized(service.sendToken.coin.code), type: .warning)
            }
        }

        amountCautionRelay.accept(caution)
    }
    
    private func sync(pluginData: [UInt8: IBitcoinPluginData]) {
        if let data = pluginData[HodlerPlugin.id] as? HodlerData {
            let days = data.lockTimeInterval.valueInSeconds / (24 * 60 * 60)
            service.update(lockTime: days)
        }else {
            service.update(lockTime: nil)
        }
    }
}

extension SendEvmViewModel {
    var title: String {
        switch service.mode {
        case .send, .prefilled: return "send.title".localized(token.coin.code)
        case .predefined: return "donate.title".localized(token.coin.code)
        }
    }

    var showAddress: Bool {
        switch service.mode {
        case .send, .prefilled: return true
        case .predefined: return false
        }
    }

    var proceedEnableDriver: Driver<Bool> {
        proceedEnabledRelay.asDriver()
    }

    var amountCautionDriver: Driver<Caution?> {
        amountCautionRelay.asDriver()
    }

    var proceedSignal: Signal<SendEvmData> {
        proceedRelay.asSignal()
    }

    var token: Token {
        service.sendToken
    }

    func didTapProceed() {
        guard case let .ready(sendData) = service.state else {
            return
        }
        proceedRelay.accept(sendData)
    }
}

extension SendEvmService.AmountError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .insufficientBalance: return "send.amount_error.balance".localized
        default: return "\(self)"
        }
    }
}
