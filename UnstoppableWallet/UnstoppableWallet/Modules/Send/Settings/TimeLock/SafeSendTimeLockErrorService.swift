import RxSwift
import RxRelay
import RxCocoa

class SafeSendTimeLockErrorService {
    private let disposeBag = DisposeBag()

    private let timeLockService: TimeLockService
    private let addressService: AddressService
    private let adapter: ISendSafeCoinAdapter

    private let errorRelay = BehaviorRelay<Error?>(value: nil)
    private(set) var error: Error? = nil {
        didSet {
            errorRelay.accept(error)
        }
    }

    init(timeLockService: TimeLockService, addressService: AddressService, adapter: ISendSafeCoinAdapter) {
        self.timeLockService = timeLockService
        self.addressService = addressService
        self.adapter = adapter

        subscribe(disposeBag, timeLockService.pluginDataObservable) { [weak self] _ in
            self?.sync()
        }
        subscribe(disposeBag, addressService.stateObservable) { [weak self] _ in
            self?.sync()
        }
    }

    private func sync() {
        guard let address = addressService.state.address else {
            error = nil
            return
        }

        do {
            _ = try adapter.validateSafe(address: address.raw)
            error = nil
        } catch {
            self.error = error.convertedError
        }
    }

}

extension SafeSendTimeLockErrorService: IErrorService {

    var errorObservable: Observable<Error?> {
        errorRelay.asObservable()
    }

}
