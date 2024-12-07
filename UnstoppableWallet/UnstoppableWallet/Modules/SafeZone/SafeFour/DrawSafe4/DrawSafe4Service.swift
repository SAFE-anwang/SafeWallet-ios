import Foundation
import RxSwift
import RxCocoa
import RxRelay
import MarketKit
import EvmKit
import HUD

class DrawSafe4Service {
    
    private var disposeBag = DisposeBag()
    private let evmKit: EvmKit.Kit
    private let provider: DrawSafe4Provider
    private let stateRelay = PublishRelay<State>()
    
    var address: String? {
        didSet {
            if address != oldValue {
                addressRelay.accept(address)
            }
        }
    }
    
    private(set) var state: State = .loading {
        didSet {
            stateRelay.accept(state)
        }
    }
    
    private var addressRelay = BehaviorRelay<String?>(value: nil)
    private let addressCautionRelay = BehaviorRelay<Caution?>(value:nil)
    
    init(provider: DrawSafe4Provider, evmKit: EvmKit.Kit) {
        self.provider = provider
        self.evmKit = evmKit
        self.address = evmKit.address.hex
    }
    
    private func drawSafe4(_ address: String) {
        state = .loading
        provider.drawSafe4RequestSingle(address: address)
            .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .subscribe(onSuccess: { [weak self] data in
                self?.state = data.issuccess ? .success(info: data.data) : .failed(error: data.message)
            }, onError: { [weak self] error in
                self?.state = .failed(error: error.localizedDescription)
            })
            .disposed(by: disposeBag)
    }
    
    func isValidAddress(_ address: String) -> Bool {
        let address = try? EvmKit.Address(hex: address)
        return address != nil
    }
}

extension DrawSafe4Service {
    
    var addressDriver: Driver<String?> {
        addressRelay.asDriver()
    }
    
    var addressCautionDriver: Driver<Caution?> {
        addressCautionRelay.asDriver()
    }
    
    var stateObservable: Observable<State> {
        stateRelay.asObservable()
    }

    func drawSafe4() {
        guard let address, isValidAddress(address) else {
            let caution = Caution(text: "safe_zone.safe4.node.input.address.error".localized, type: .error)
            addressCautionRelay.accept(caution)
            return
        }
        addressCautionRelay.accept(nil)
        drawSafe4(address)
    }
}

extension DrawSafe4Service {

    enum State {
        case loading
        case success(info: DrawSafe4Info?)
        case failed(error: String?)
    }
}

