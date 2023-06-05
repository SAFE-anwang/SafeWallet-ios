import Foundation
import RxSwift
import RxCocoa
import RxRelay
import HsToolKit
import Hodler

class SendSafeCoinAdapterService {
    private let disposeBag = DisposeBag()
    private let queue = DispatchQueue(label: "io.horizontalsystems.unstoppable.send.safe_adapter_service", qos: .userInitiated)

    private let feeRateService: FeeRateService
    private let amountInputService: IAmountInputService
    private let addressService: AddressService
    private let timeLockService: TimeLockService?
    private let btcBlockchainManager: BtcBlockchainManager
    private let adapter: ISendSafeCoinAdapter

    let inputOutputOrderService: InputOutputOrderService

    // Outputs
    let feeStateRelay = BehaviorRelay<DataStatus<Decimal>>(value: .loading)
    var feeState: DataStatus<Decimal> = .loading {
        didSet {
            if !feeState.equalTo(oldValue) {
                feeStateRelay.accept(feeState)
            }
        }
    }

    let availableBalanceRelay = BehaviorRelay<DataStatus<Decimal>>(value: .loading)
    var availableBalance: DataStatus<Decimal> = .loading {
        didSet {
            if !availableBalance.equalTo(oldValue) {
                availableBalanceRelay.accept(availableBalance)
            }
        }
    }

    let minimumSendAmountRelay = BehaviorRelay<Decimal>(value: 0)
    var minimumSendAmount: Decimal = 0 {
        didSet {
            if minimumSendAmount != oldValue {
                minimumSendAmountRelay.accept(minimumSendAmount)
            }
        }
    }

    let maximumSendAmountRelay = BehaviorRelay<Decimal?>(value: nil)
    var maximumSendAmount: Decimal? = nil {
        didSet {
            if maximumSendAmount != oldValue {
                maximumSendAmountRelay.accept(maximumSendAmount)
            }
        }
    }

    init(feeRateService: FeeRateService, amountInputService: IAmountInputService, addressService: AddressService,
         inputOutputOrderService: InputOutputOrderService, timeLockService: TimeLockService?, btcBlockchainManager: BtcBlockchainManager, adapter: ISendSafeCoinAdapter) {
        self.feeRateService = feeRateService
        self.amountInputService = amountInputService
        self.addressService = addressService
        self.timeLockService = timeLockService
        self.inputOutputOrderService = inputOutputOrderService
        self.btcBlockchainManager = btcBlockchainManager
        self.adapter = adapter
        
        sync(feeRate: .completed(10))
        
        subscribe(disposeBag, amountInputService.amountObservable) { [weak self] _ in
            self?.sync(updatedFrom: .amount)
        }
        subscribe(disposeBag, addressService.stateObservable) { [weak self] _ in
            self?.sync(updatedFrom: .address)
        }

        if let timeLockService = timeLockService {
            subscribe(disposeBag, timeLockService.pluginDataObservable) { [weak self] _ in
                self?.sync(updatedFrom: .pluginData)
            }
        }

        subscribe(disposeBag, feeRateService.statusObservable) { [weak self] in
            self?.sync(feeRate: $0)
        }

        minimumSendAmount = adapter.minimumSendAmountSafe(address: addressService.state.address?.raw)
     //   maximumSendAmount = adapter.maximumSendAmount(pluginData: pluginData)
    }

    private func sync(feeRate: DataStatus<Int>? = nil, updatedFrom: UpdatedField = .feeRate) {
        let feeRate = feeRate ?? feeRateService.status
        let amount = amountInputService.amount

        switch feeRate {
        case .loading:
            guard !amount.isZero else {      // force update fee for bitcoin, when clear amount to zero value
                feeState = .completed(0)
                return
            }

            feeState = .loading
        case .failed(let error):
            feeState = .failed(error)
        case .completed(let feeRate):
            update(feeRate: feeRate, amount: amount, address: addressService.state.address?.raw, pluginData: pluginData, updatedFrom: updatedFrom)
        }
    }

    private func update(feeRate: Int, amount: Decimal, address: String?, pluginData: [UInt8: IBitcoinPluginData], updatedFrom: UpdatedField) {
        queue.async { [weak self] in
            if let fee = self?.adapter.feeSafe(amount: amount, address: address) {
                self?.feeState = .completed(fee)
            }
            if updatedFrom != .amount,
               let availableBalance = self?.adapter.availableBalanceSafe(address: address){
                self?.availableBalance = .completed(availableBalance)
            }
//            if updatedFrom == .pluginData {
//                self?.maximumSendAmount = self?.adapter.maximumSendAmount(pluginData: pluginData)
//            }
            if updatedFrom == .address {
                self?.minimumSendAmount = self?.adapter.minimumSendAmountSafe(address: address) ?? 0
            }
        }
    }

    private var pluginData: [UInt8: IBitcoinPluginData] {
        timeLockService?.pluginData ?? [:]
    }

}

extension SendSafeCoinAdapterService: ISendXFeeValueService, IAvailableBalanceService, ISendXSendAmountBoundsService {

    var feeStateObservable: Observable<DataStatus<Decimal>> {
        feeStateRelay.asObservable()
    }

    var availableBalanceObservable: Observable<DataStatus<Decimal>> {
        availableBalanceRelay.asObservable()
    }

    var minimumSendAmountObservable: Observable<Decimal> {
        minimumSendAmountRelay.asObservable()
    }

    var maximumSendAmountObservable: Observable<Decimal?> {
        maximumSendAmountRelay.asObservable()
    }

    func validate(address: String) throws {
        try adapter.validateSafe(address: address)
    }

}

extension SendSafeCoinAdapterService: ISendService {

    func sendSingle(logger: Logger) -> Single<Void> {
        let address: Address
        switch addressService.state {
        case .success(let sendAddress): address = sendAddress
        case .fetchError(let error): return Single.error(error)
        default: return Single.error(AppError.addressInvalid)
        }

        guard case let .completed(feeRate) = feeRateService.status else {
            return Single.error(SendTransactionError.noFee)
        }

        guard !amountInputService.amount.isZero else {
            return Single.error(SendTransactionError.wrongAmount)
        }
        if let data = pluginData[HodlerPlugin.id] as? HodlerData {

            return adapter.sendSingle(amount: amountInputService.amount, address: address.raw, sortMode: .shuffle, logger: logger, lockedTimeInterval: data.lockTimeInterval, reverseHex: nil)
        }
       // let sortMode = btcBlockchainManager.transactionSortMode(blockchainType: adapter.blockchainType)
        return adapter.sendSingle(amount: amountInputService.amount, address: address.raw, sortMode: .shuffle, logger: logger, lockedTimeInterval: nil, reverseHex: nil)
    }

}

extension SendSafeCoinAdapterService {

    private enum UpdatedField: String {
        case amount, address, pluginData, feeRate
    }

}

